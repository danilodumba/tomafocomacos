#!/bin/bash
#
# T-25 — Empacota o Tomafoco para distribuição fora da Mac App Store:
# build Release → assinatura Developer ID → DMG → notarização → staple.
#
# Uso:
#   ./scripts/release.sh                 # pipeline completo (exige Developer ID + credencial)
#   SKIP_NOTARIZE=1 ./scripts/release.sh # para até o DMG (útil para testar o empacotamento)
#
# Pré-requisitos (ver docs/release.md):
#   - Certificado "Developer ID Application" instalado no chaveiro
#   - Perfil de notarização salvo:  xcrun notarytool store-credentials tomafoco
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="Tomafoco"
SCHEME="Tomafoco"
ENTITLEMENTS="App/Resources/${APP_NAME}.entitlements"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-tomafoco}"
BUILD_DIR="$PROJECT_ROOT/build"
STAGE_DIR="$BUILD_DIR/dmg-stage"
# Onde o DMG e o appcast.xml ficam publicados. Precisa bater com `SUFeedURL` no project.yml —
# se divergir, o Sparkle acha o feed mas o download 404.
UPDATE_BASE_URL="${UPDATE_BASE_URL:-https://tomafoco.dds.tec.br/downloads}"
UPDATE_LINK="${UPDATE_LINK:-https://tomafoco.dds.tec.br}"
# Ferramentas do Sparkle (generate_appcast, sign_update) vêm no artefato binário do SPM.
# Os pacotes são clonados FORA de build/ porque o script faz `rm -rf build` a cada release —
# deixá-los lá custaria rebaixar o XCFramework do Sparkle (dezenas de MB) toda vez.
SPM_CACHE="$PROJECT_ROOT/.spm-cache"
SPARKLE_BIN="$SPM_CACHE/artifacts/sparkle/Sparkle/bin"

info()  { printf '\033[36m▸\033[0m %s\n' "$1"; }
ok()    { printf '\033[32m✓\033[0m %s\n' "$1"; }
fail()  { printf '\033[31m✗\033[0m %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- preflight

info "Verificando pré-requisitos…"

command -v xcodegen >/dev/null || fail "xcodegen ausente. Instale com: brew install xcodegen"

# O nome completo do certificado é o que o codesign espera.
# `|| true`: sem o certificado o grep sai com 1 e, sob `set -e`, mataria o script
# antes da mensagem que explica o que fazer.
IDENTITY="${IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" \
    | head -1 \
    | sed -E 's/.*"(.+)"$/\1/' || true)}"

if [[ -z "$IDENTITY" ]]; then
    fail "Nenhum certificado 'Developer ID Application' no chaveiro.
   Sem ele o app não pode ser distribuído: o macOS bloqueia no primeiro clique.
   Crie em https://developer.apple.com/account/resources/certificates (exige o
   Apple Developer Program pago) e veja docs/release.md."
fi
ok "Certificado: $IDENTITY"

if [[ -z "${SKIP_NOTARIZE:-}" ]]; then
    xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1 \
        || fail "Credencial de notarização '$KEYCHAIN_PROFILE' inválida ou ausente.
   Crie em modo interativo (a senha não vai para o histórico do shell):
     xcrun notarytool store-credentials $KEYCHAIN_PROFILE
   Ou, melhor, com chave de API do App Store Connect (sem Apple ID/2FA):
     xcrun notarytool store-credentials $KEYCHAIN_PROFILE \\
       --key AuthKey_XXXX.p8 --key-id XXXX --issuer <UUID>
   Erro 401 recorrente? Ver a seção de diagnóstico em docs/release.md."
    ok "Credencial de notarização: $KEYCHAIN_PROFILE"
fi

# Chave privada EdDSA do Sparkle: assina o appcast. Sem ela o app instalado hoje ignora
# qualquer atualização — e é o que impede terceiros de servirem um "update" forjado.
GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
if [[ -z "${SKIP_APPCAST:-}" ]]; then
    security find-generic-password -s "https://sparkle-project.org" -a "ed25519" >/dev/null 2>&1 \
        || fail "Chave privada EdDSA do Sparkle ausente no chaveiro.
   Gere UMA vez (guarde o backup impresso/offline — perdê-la impede atualizar quem já instalou):
     ./scripts/sparkle-generate-keys.sh
   Depois cole a chave pública em SUPublicEDKey no project.yml."
    ok "Chave EdDSA do Sparkle encontrada no chaveiro"
fi

# ---------------------------------------------------------------- build

info "Gerando projeto e compilando em Release…"
xcodegen generate >/dev/null

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Assinatura é feita manualmente no passo seguinte: dá controle explícito sobre
# entitlements, hardened runtime e timestamp, em vez de depender da config do Xcode.
# ARCHS/ONLY_ACTIVE_ARCH explícitos: sem eles o Xcode compila só a arquitetura da máquina
# (arm64 aqui), o app não abre em Mac Intel e o generate_appcast ainda grava
# <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements> — o que exclui o Intel
# também das ATUALIZAÇÕES, não só do primeiro download.
xcodebuild -project "${APP_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -clonedSourcePackagesDirPath "$SPM_CACHE" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    build >"$BUILD_DIR/build.log" 2>&1 \
    || { tail -30 "$BUILD_DIR/build.log"; fail "Falha ao compilar (log em $BUILD_DIR/build.log)"; }

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/${APP_NAME}.app"
[[ -d "$APP_PATH" ]] || fail "App não encontrado em $APP_PATH"

# Versão lida do app JÁ compilado: o Info.plist do bundle tem as variáveis
# ($(MARKETING_VERSION) etc.) expandidas pelo Xcode. Ler do plist-fonte devolveria
# o literal "$(MARKETING_VERSION)" e quebraria o nome do DMG.
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0")"
ok "Compilado: ${APP_NAME}.app ($VERSION)"

# Um app publicado com a chave pública placeholder nunca mais aceita atualização: o Sparkle
# rejeita toda assinatura e não há como corrigir remotamente. Barra aqui.
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")"
case "$PUBLIC_KEY" in
    ""|SUBSTITUIR_*)
        MSG="SUPublicEDKey ainda é placeholder no project.yml.
   Rode ./scripts/sparkle-generate-keys.sh e cole a chave pública lá.
   Publicar assim entrega um app que jamais conseguirá se atualizar."
        # Em release de verdade isso é fatal; num teste de empacotamento (SKIP_NOTARIZE)
        # é só um aviso — dá para validar o DMG antes de existir chave.
        if [[ -n "${SKIP_NOTARIZE:-}" ]]; then
            printf '\033[33m⚠\033[0m  %s\n' "$MSG"
        else
            fail "$MSG"
        fi
        ;;
esac

# ---------------------------------------------------------------- assinatura

info "Assinando com Developer ID…"

# O Sparkle embute executáveis dentro do app (Updater.app, Autoupdate, XPC services). Cada um
# precisa da PRÓPRIA assinatura, e de dentro para fora: assinar só o .app externo deixa o
# conteúdo aninhado sem selo e a notarização REJEITA o pacote inteiro.
#
# Os aninhados NÃO recebem o entitlements do app: `apple-events` é permissão para o Tomafoco
# pilotar navegadores; o instalador não tem o que fazer com ela (menor privilégio).
#
# Assina-se `Versions/<X>` e não `Sparkle.framework`: em bundle versionado o caminho curto é um
# symlink para `Versions/Current`, e é assim que a própria documentação do Sparkle manda fazer.
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
    FW_VERSION_DIR="$(find "$SPARKLE_FW/Versions" -maxdepth 1 -mindepth 1 -type d \
        ! -name Current | head -1)"
    [[ -n "$FW_VERSION_DIR" ]] \
        || fail "Sparkle.framework sem diretório de versão — o layout do framework mudou;
   confira o passo de assinatura em docs/release.md antes de publicar."

    for nested in \
        "$FW_VERSION_DIR"/XPCServices/*.xpc \
        "$FW_VERSION_DIR"/Updater.app \
        "$FW_VERSION_DIR"/Autoupdate \
        "$FW_VERSION_DIR"
    do
        [[ -e "$nested" ]] || continue
        info "  ↳ ${nested#"$APP_PATH"/}"
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$nested"
    done
fi

# --options runtime  → Hardened Runtime, exigido pela notarização
# --timestamp        → carimbo de tempo seguro, também exigido
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    "$APP_PATH"

# `--deep` verifica o conteúdo aninhado também: pega framework do Sparkle que tenha ficado
# sem selo antes de a notarização gastar minutos para reprovar.
codesign --verify --deep --strict "$APP_PATH" \
    || fail "Verificação profunda falhou — algum bundle aninhado ficou sem assinatura."

codesign --verify --strict --verbose=2 "$APP_PATH" 2>&1 | tail -2
ok "Assinado e verificado"

# ------------------------------------------------- notarização do .app

# O .app é notarizado ANTES de entrar no DMG para receber o próprio ticket.
# Grampear só o DMG não basta: ao arrastar o app para /Applications, o ticket fica
# para trás, e num Mac sem rede o Gatekeeper barra a primeira abertura.
if [[ -z "${SKIP_NOTARIZE:-}" ]]; then
    info "Notarizando o app (1/2)…"
    APP_ZIP="$BUILD_DIR/${APP_NAME}.zip"
    # `ditto -c -k --keepParent` preserva a estrutura do bundle; `zip` comum corrompe symlinks.
    ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
    xcrun notarytool submit "$APP_ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$APP_PATH"
    rm -f "$APP_ZIP"
    ok "App notarizado e grampeado"
fi

# ---------------------------------------------------------------- dmg

info "Montando o DMG…"

DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
# Atalho para /Applications: o usuário arrasta o app para instalar.
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

# O DMG também é assinado: sem isso o Gatekeeper reclama do container.
codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
ok "DMG: $DMG_PATH"

# ---------------------------------------------------------------- notarização

if [[ -z "${SKIP_NOTARIZE:-}" ]]; then
    info "Notarizando o DMG (2/2)…"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    info "Grampeando o ticket no DMG…"
    xcrun stapler staple "$DMG_PATH"
    ok "Ticket grampeado"
fi

# ---------------------------------------------------------------- appcast

# O appcast é gerado DEPOIS do staple: o `generate_appcast` calcula tamanho e assinatura
# EdDSA do arquivo final. Grampear depois mudaria o DMG e invalidaria a assinatura.
if [[ -n "${SKIP_APPCAST:-}" ]]; then
    printf '\033[33m⚠\033[0m  SKIP_APPCAST ativo: nenhum feed foi gerado.\n'
    exit 0
fi

info "Gerando o appcast (feed do Sparkle)…"

[[ -x "$GENERATE_APPCAST" ]] || fail "generate_appcast não encontrado em $SPARKLE_BIN
   (o artefato do Sparkle é baixado pelo SPM durante o build — rode o script de novo)."

APPCAST_DIR="$BUILD_DIR/appcast"
rm -rf "$APPCAST_DIR"
mkdir -p "$APPCAST_DIR"
cp "$DMG_PATH" "$APPCAST_DIR/"

# Notas de versão opcionais: o generate_appcast adota o HTML de mesmo nome do DMG e o
# Sparkle o exibe no diálogo de atualização. Sem o arquivo, o item sai sem descrição.
NOTES_SRC="$PROJECT_ROOT/docs/release-notes/${VERSION}.html"
NOTES_OUT="$APPCAST_DIR/${APP_NAME}-${VERSION}.html"
if [[ -f "$NOTES_SRC" ]]; then
    cp "$NOTES_SRC" "$NOTES_OUT"
    ok "Notas de versão: $NOTES_SRC"
else
    printf '\033[33m⚠\033[0m  Sem notas de versão em %s — o item do appcast sai sem descrição.\n' \
        "docs/release-notes/${VERSION}.html"
fi

# A chave privada sai do chaveiro (nunca de arquivo no repo). O prefixo precisa terminar em
# "/": o generate_appcast concatena com o nome do arquivo sem inserir separador.
"$GENERATE_APPCAST" \
    --download-url-prefix "${UPDATE_BASE_URL%/}/" \
    --link "$UPDATE_LINK" \
    "$APPCAST_DIR"

APPCAST_PATH="$APPCAST_DIR/appcast.xml"
[[ -f "$APPCAST_PATH" ]] || fail "generate_appcast não produziu $APPCAST_PATH"
ok "Appcast: $APPCAST_PATH"

# ---------------------------------------------------------------- verificação

if [[ -n "${SKIP_NOTARIZE:-}" ]]; then
    printf '\n\033[33m⚠\033[0m  SKIP_NOTARIZE ativo: o DMG NÃO foi notarizado.\n'
    printf '   Em outro Mac o macOS vai recusar a abertura, e o appcast acima só serve\n'
    printf '   para conferir o formato. Não publique.\n'
    exit 0
fi

info "Verificação final (simula o que o Gatekeeper faz)…"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
ok "Assinado, notarizado e grampeado: $DMG_PATH"

# ---------------------------------------------------------------- publicação

# Só o upload torna a atualização real: enquanto o appcast antigo estiver no ar, quem já tem o
# app instalado continua vendo a versão anterior.
printf '\n'
info "Falta publicar em ${UPDATE_BASE_URL}:"
printf '   %s\n' "$DMG_PATH" "$APPCAST_DIR/appcast.xml"
# `if` e não `[[ … ]] && …`: sob `set -e`, o `&&` que falha derruba o script inteiro quando
# não há notas de versão — justamente o caso comum.
if [[ -f "$NOTES_OUT" ]]; then printf '   %s\n' "$NOTES_OUT"; fi

if [[ -n "${UPDATE_UPLOAD_DEST:-}" ]]; then
    # Ex.: UPDATE_UPLOAD_DEST="usuario@host:/var/www/tomafoco/downloads/"
    info "Enviando via rsync para $UPDATE_UPLOAD_DEST…"
    # O DMG sobe ANTES do appcast: publicar o feed primeiro deixaria uma janela em que o
    # Sparkle anuncia a versão nova e o download ainda dá 404.
    rsync -av "$DMG_PATH" "$UPDATE_UPLOAD_DEST"
    if [[ -f "$NOTES_OUT" ]]; then rsync -av "$NOTES_OUT" "$UPDATE_UPLOAD_DEST"; fi
    rsync -av "$APPCAST_DIR/appcast.xml" "$UPDATE_UPLOAD_DEST"
    ok "Publicado. Feed: ${UPDATE_BASE_URL%/}/appcast.xml"
else
    printf '   (defina UPDATE_UPLOAD_DEST=usuario@host:/caminho/ para o script subir via rsync)\n'
    printf '   \033[33mSuba o DMG ANTES do appcast.xml\033[0m — o feed novo apontando para um DMG\n'
    printf '   que ainda não subiu faz o Sparkle falhar o download em quem checar nesse intervalo.\n'
fi

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

# ---------------------------------------------------------------- build

info "Gerando projeto e compilando em Release…"
xcodegen generate >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    App/Resources/Info.generated.plist 2>/dev/null || echo "1.0")"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Assinatura é feita manualmente no passo seguinte: dá controle explícito sobre
# entitlements, hardened runtime e timestamp, em vez de depender da config do Xcode.
xcodebuild -project "${APP_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    build >"$BUILD_DIR/build.log" 2>&1 \
    || { tail -30 "$BUILD_DIR/build.log"; fail "Falha ao compilar (log em $BUILD_DIR/build.log)"; }

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/${APP_NAME}.app"
[[ -d "$APP_PATH" ]] || fail "App não encontrado em $APP_PATH"
ok "Compilado: ${APP_NAME}.app ($VERSION)"

# ---------------------------------------------------------------- assinatura

info "Assinando com Developer ID…"

# --options runtime  → Hardened Runtime, exigido pela notarização
# --timestamp        → carimbo de tempo seguro, também exigido
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    "$APP_PATH"

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

if [[ -n "${SKIP_NOTARIZE:-}" ]]; then
    printf '\n\033[33m⚠\033[0m  SKIP_NOTARIZE ativo: o DMG NÃO foi notarizado.\n'
    printf '   Em outro Mac o macOS vai recusar a abertura. Só serve para teste local.\n'
    exit 0
fi

# ---------------------------------------------------------------- notarização

info "Notarizando o DMG (2/2)…"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

info "Grampeando o ticket no DMG…"
xcrun stapler staple "$DMG_PATH"
ok "Ticket grampeado"

# ---------------------------------------------------------------- verificação

info "Verificação final (simula o que o Gatekeeper faz)…"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
ok "Pronto para distribuir: $DMG_PATH"

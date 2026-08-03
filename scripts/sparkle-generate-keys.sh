#!/bin/bash
#
# Gera (uma única vez) o par de chaves EdDSA que assina as atualizações do Sparkle.
#
# A chave PRIVADA fica no chaveiro do login — nunca em arquivo do repositório. A PÚBLICA vai
# embutida no app, em `SUPublicEDKey` (project.yml).
#
# ⚠️ Perder a chave privada é irreversível: todo mundo que já instalou o Tomafoco passa a
#    ignorar qualquer atualização (o app só aceita appcast assinado pela chave que ele conhece),
#    e a única saída vira pedir reinstalação manual. Exporte um backup e guarde offline.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

SPM_CACHE="$PROJECT_ROOT/.spm-cache"
GENERATE_KEYS="$SPM_CACHE/artifacts/sparkle/Sparkle/bin/generate_keys"

info() { printf '\033[36m▸\033[0m %s\n' "$1"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '\033[31m✗\033[0m %s\n' "$1" >&2; exit 1; }

# As ferramentas do Sparkle vêm no artefato binário do SPM — só existem depois que o
# gerenciador de pacotes resolve as dependências.
if [[ ! -x "$GENERATE_KEYS" ]]; then
    info "Baixando as ferramentas do Sparkle (primeira vez, pode demorar)…"
    command -v xcodegen >/dev/null || fail "xcodegen ausente. Instale com: brew install xcodegen"
    xcodegen generate >/dev/null
    xcodebuild -project Tomafoco.xcodeproj -scheme Tomafoco \
        -clonedSourcePackagesDirPath "$SPM_CACHE" \
        -resolvePackageDependencies >/dev/null
fi
[[ -x "$GENERATE_KEYS" ]] || fail "generate_keys não apareceu em $SPM_CACHE/artifacts/sparkle/Sparkle/bin"

if security find-generic-password -s "https://sparkle-project.org" -a "ed25519" >/dev/null 2>&1; then
    ok "Já existe uma chave privada no chaveiro — nada foi gerado."
    info "Chave pública correspondente (é ela que vai em SUPublicEDKey):"
    "$GENERATE_KEYS" -p
else
    info "Gerando o par de chaves…"
    # O macOS pode pedir sua senha para autorizar a escrita no chaveiro.
    "$GENERATE_KEYS"
fi

cat <<'EOF'

Próximos passos
---------------
1. Cole a chave pública acima em `SUPublicEDKey`, no project.yml.
2. Faça um backup da chave PRIVADA e guarde fora do computador:

     .spm-cache/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/tomafoco-sparkle-key.txt

   Depois mova esse arquivo para um gerenciador de senhas / cofre e apague o original.
   Não versione: qualquer um com essa chave consegue publicar uma "atualização" que o
   Tomafoco instalado vai aceitar e executar.
EOF

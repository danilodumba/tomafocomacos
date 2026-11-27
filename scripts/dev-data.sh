#!/usr/bin/env bash
# Copia os dados do Tomafoco de PRODUÇÃO para o build de desenvolvimento ("Tomafoco Dev").
#
#   make dev-data            # cria/atualiza a cópia (substitui a cópia dev anterior)
#
# - Banco: `sqlite3 .backup` (cópia consistente mesmo com o Tomafoco de produção aberto — copiar
#   os arquivos .store/-wal/-shm na mão pode pegar uma transação pela metade).
# - Preferências: exporta o domínio `com.dsdumba.tomafoco` para `com.dsdumba.tomafoco.dev` e, na
#   cópia, DESLIGA o que tocaria em coisas reais fora do app: sincronização de conclusão com o
#   Lembretes e bloqueio contínuo de apps/sites (as duas instâncias bloqueariam em dobro).
# - Nunca escreve na pasta nem nas preferências de produção.
set -euo pipefail

PROD_DIR="$HOME/Library/Application Support/Tomafoco"
DEV_DIR="$HOME/Library/Application Support/Tomafoco-Dev"
# Por caminho, não por nome: existe um container de sandbox antigo em
# ~/Library/Containers/com.dsdumba.tomafoco, e `defaults … com.dsdumba.tomafoco` lê o domínio de
# lá (vazio) em vez das preferências reais do app (que não roda em sandbox).
PROD_PREFS="$HOME/Library/Preferences/com.dsdumba.tomafoco.plist"
DEV_DOMAIN="com.dsdumba.tomafoco.dev"

if pgrep -f "Tomafoco Dev|Debug/Tomafoco.app" >/dev/null 2>&1; then
    echo "✋ Feche o Tomafoco Dev antes (ele está com o banco dev aberto)." >&2
    exit 1
fi
[[ -f "$PROD_DIR/Tomafoco.store" ]] || { echo "Banco de produção não encontrado em $PROD_DIR" >&2; exit 1; }

mkdir -p "$DEV_DIR"
rm -f "$DEV_DIR"/Tomafoco.store "$DEV_DIR"/Tomafoco.store-wal "$DEV_DIR"/Tomafoco.store-shm
sqlite3 "$PROD_DIR/Tomafoco.store" ".backup '$DEV_DIR/Tomafoco.store'"
echo "✓ Banco copiado → $DEV_DIR/Tomafoco.store ($(du -h "$DEV_DIR/Tomafoco.store" | cut -f1))"
# Sem os JSON antigos de propósito: o banco já traz o `StoreMeta`, então o importador não roda.

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if [[ -f "$PROD_PREFS" ]] && defaults export "$PROD_PREFS" "$TMP/prefs.plist" 2>/dev/null; then
    python3 -I - "$TMP/prefs.plist" <<'PY'
import json, plistlib, sys
path = sys.argv[1]
with open(path, "rb") as f:
    prefs = plistlib.load(f)
if "tomafoco.configuration" not in prefs and "tomafoco.blockList" not in prefs:
    # `defaults export` devolve plist vazio (sem erro) quando não alcança o cfprefsd — ex.: shell
    # em sandbox. Importar isso apagaria as preferências dev sem copiar nada.
    sys.exit("✗ As preferências de produção vieram vazias — rode fora de sandbox.")
# Estado do Sparkle e de janelas é da instalação de produção — não levar.
for key in [k for k in prefs if k.startswith("SU") or k.startswith("NSWindow") or k.startswith("NSStatusItem")]:
    del prefs[key]
raw = prefs.get("tomafoco.configuration")
if isinstance(raw, bytes):
    config = json.loads(raw)
    config["syncReminderCompletion"] = False
    config["blockAppsWhileRunning"] = False
    config["blockSitesWhileRunning"] = False
    prefs["tomafoco.configuration"] = json.dumps(config).encode()
with open(path, "wb") as f:
    plistlib.dump(prefs, f, fmt=plistlib.FMT_BINARY)
PY
    defaults delete "$DEV_DOMAIN" >/dev/null 2>&1 || true
    defaults import "$DEV_DOMAIN" "$TMP/prefs.plist"
    echo "✓ Preferências copiadas → $DEV_DOMAIN (sync com Lembretes e bloqueio contínuo desligados)"
else
    echo "• Sem preferências de produção para copiar."
fi

echo "Pronto. Rode o build Debug (\"Tomafoco Dev\" — aparece com DEV na barra de menus)."

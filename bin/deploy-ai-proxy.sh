#!/usr/bin/env bash
#
# GeoKing — redéploie le Worker Cloudflare « proxy Gemini » (wrangler deploy).
# Pour le 1er provisionnement (KV + secret), utilise plutôt setup-ai-proxy.sh.
#
# Usage : ./scripts/deploy-ai-proxy.sh
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
gk_project_init
cd "$ROOT"

WORKER_DIR="$ROOT/worker"
CFG="$WORKER_DIR/wrangler.jsonc"
[ -d "$WORKER_DIR" ] || die "Dossier worker/ introuvable : $WORKER_DIR"

lp(){ [ -f "$LP" ] && grep "^$1=" "$LP" 2>/dev/null | cut -d= -f2- || true; }
export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(lp CLOUDFLARE_API_TOKEN)}"
export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-$(lp CLOUDFLARE_ACCOUNT_ID)}"

head_ "🚀  Déploiement du Worker proxy Gemini"
grep -q 'REPLACE_WITH_KV_ID' "$CFG" && die "KV non configuré — lance d'abord ./scripts/setup-ai-proxy.sh"
need npx
[ -d "$WORKER_DIR/node_modules" ] || ( cd "$WORKER_DIR" && npm install --no-fund --no-audit >/dev/null )
( cd "$WORKER_DIR" && npx --yes wrangler deploy )
ok "Déploiement terminé."

#!/usr/bin/env bash
#
# GeoKing — provisionne et déploie le Worker Cloudflare « proxy Gemini ».
# La clé GEMINI_API_KEY ne vit que côté Worker (Secret), jamais dans l'APK.
#
# Usage (via le wrapper scripts/ du projet) :
#   ./scripts/setup-ai-proxy.sh [all|kv|secret|deploy|push] [--push]
#     all      KV + secret + deploy (défaut)
#     kv       crée le namespace KV et l'inscrit dans worker/wrangler.jsonc
#     secret   pousse GEMINI_API_KEY comme Worker Secret
#     deploy   wrangler deploy + synchronise AI_PROXY_URL (local.properties)
#     push     pousse les secrets GitHub (CLOUDFLARE_*, AI_PROXY_URL, GEMINI_API_KEY)
#     --push   après « all », enchaîne aussi l'étape push
#
# Auth Cloudflare : CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID (local.properties
# ou env). Sinon wrangler bascule sur l'OAuth navigateur (wrangler login).
set -euo pipefail

PUSH=false
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --push|-p) PUSH=true; shift ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]:-all}"

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
gk_project_init
cd "$ROOT"

WORKER_DIR="$ROOT/worker"
CFG="$WORKER_DIR/wrangler.jsonc"
[ -d "$WORKER_DIR" ] || die "Dossier worker/ introuvable : $WORKER_DIR"

AI_PROXY_URL_RESOLVED=""

lp(){ [ -f "$LP" ] && grep "^$1=" "$LP" 2>/dev/null | cut -d= -f2- || true; }

# Cloudflare auth from local.properties → env so wrangler runs non-interactively.
export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(lp CLOUDFLARE_API_TOKEN)}"
export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-$(lp CLOUDFLARE_ACCOUNT_ID)}"

wr(){ ( cd "$WORKER_DIR" && npx --yes wrangler "$@" ); }

ensure_deps(){
  need npx
  if [ ! -d "$WORKER_DIR/node_modules" ]; then
    step "Installation des dépendances worker (npm install)"
    ( cd "$WORKER_DIR" && npm install --no-fund --no-audit >/dev/null ) || die "npm install a échoué"
    ok "Dépendances worker installées"
  fi
}

step_kv(){
  head_ "🗄️  Namespace KV (quota + cache)"
  if ! grep -q 'REPLACE_WITH_KV_ID' "$CFG"; then
    ok "KV déjà configuré dans worker/wrangler.jsonc"
    return 0
  fi
  ensure_deps
  local binding="${CF_KV_BINDING:-AI_KV}" out id
  step "Création du namespace KV « $binding »"
  out="$(wr kv namespace create "$binding" 2>&1)" || { say "$out"; die "wrangler kv namespace create a échoué"; }
  id="$(printf '%s\n' "$out" | grep -oE '[0-9a-f]{32}' | head -n1)"
  [ -n "$id" ] || { say "$out"; die "ID du namespace KV introuvable dans la sortie wrangler"; }
  sedi "s/REPLACE_WITH_KV_ID/$id/" "$CFG"
  ok "KV créé → $id (inscrit dans worker/wrangler.jsonc)"
}

step_secret(){
  head_ "🔑  Secret Worker GEMINI_API_KEY"
  ensure_deps
  local k; k="$(lp GEMINI_API_KEY)"
  if [ -z "$k" ]; then
    show_url "${GEMINI_API_KEYS:-https://aistudio.google.com/apikey}"
    k="$(ask "Clé Gemini (Entrée pour passer)")"
  fi
  if [ -z "$k" ]; then warn "Aucune clé fournie — Worker Secret non défini"; return 0; fi
  printf '%s' "$k" | wr secret put GEMINI_API_KEY >/dev/null && ok "GEMINI_API_KEY défini sur le Worker"
  # WEB_CLIENT_ID (variable publique, usage futur) si présente localement.
  local web; web="$(lp WEB_CLIENT_ID)"
  if [ -n "$web" ] && grep -q '"WEB_CLIENT_ID": ""' "$CFG"; then
    sedi "s#\"WEB_CLIENT_ID\": \"\"#\"WEB_CLIENT_ID\": \"$web\"#" "$CFG"
    ok "WEB_CLIENT_ID inscrit dans worker/wrangler.jsonc"
  fi
}

step_deploy(){
  head_ "🚀  Déploiement du Worker"
  ensure_deps
  grep -q 'REPLACE_WITH_KV_ID' "$CFG" && die "KV non configuré — lance d'abord : ./scripts/setup-ai-proxy.sh kv"
  local out url
  out="$(wr deploy 2>&1)" || { say "$out"; die "wrangler deploy a échoué"; }
  say "$out"
  url="$(printf '%s\n' "$out" | grep -oE 'https://[a-zA-Z0-9.-]+\.workers\.dev' | head -n1)"
  if [ -n "$url" ]; then
    AI_PROXY_URL_RESOLVED="$url/v1/generate"
    set_local_prop AI_PROXY_URL "$AI_PROXY_URL_RESOLVED"
    ok "Worker déployé → $AI_PROXY_URL_RESOLVED"
  else
    warn "URL workers.dev non détectée — renseigne AI_PROXY_URL à la main (.../v1/generate)"
  fi
}

step_push(){
  head_ "🔄  Secrets GitHub (CI Worker + build app)"
  need gh
  local tok="$CLOUDFLARE_API_TOKEN" acc="$CLOUDFLARE_ACCOUNT_ID"
  [ -n "$tok" ] || tok="$(ask "CLOUDFLARE_API_TOKEN (Entrée pour passer)")"
  [ -n "$acc" ] || acc="$(ask "CLOUDFLARE_ACCOUNT_ID (Entrée pour passer)")"
  [ -n "$tok" ] && printf '%s' "$tok" | gh secret set CLOUDFLARE_API_TOKEN && ok "CLOUDFLARE_API_TOKEN poussé"
  [ -n "$acc" ] && printf '%s' "$acc" | gh secret set CLOUDFLARE_ACCOUNT_ID && ok "CLOUDFLARE_ACCOUNT_ID poussé"
  local url; url="${AI_PROXY_URL_RESOLVED:-$(lp AI_PROXY_URL)}"
  [ -n "$url" ] && printf '%s' "$url" | gh secret set AI_PROXY_URL && ok "AI_PROXY_URL poussé (build CI)"
  local k; k="$(lp GEMINI_API_KEY)"
  [ -n "$k" ] && printf '%s' "$k" | gh secret set GEMINI_API_KEY && ok "GEMINI_API_KEY (re)poussé (CI Worker)"
}

case "${1:-all}" in
  kv)     step_kv ;;
  secret) step_secret ;;
  deploy) step_deploy ;;
  push)   step_push ;;
  all)
    head_ "✨  Proxy IA Cloudflare · ${PROJECT_NAME:-app}"
    info_box \
      "Worker : ${CF_WORKER_NAME:-voir worker/wrangler.jsonc}" \
      "Config : worker/wrangler.jsonc" \
      "La clé Gemini reste côté Worker (jamais dans l'APK)."
    if [ -n "$CLOUDFLARE_API_TOKEN" ]; then ok "Auth Cloudflare via token (local.properties/env)"
    else hint "Pas de token — wrangler utilisera l'OAuth navigateur (wrangler login)"; fi
    step_kv; step_secret; step_deploy
    if $PUSH; then step_push; else hint "Astuce : --push pour synchroniser les secrets GitHub (CI)"; fi
    ;;
  *) die "Usage : setup-ai-proxy.sh [all|kv|secret|deploy|push] [--push]" ;;
esac

blank
ok "Terminé."

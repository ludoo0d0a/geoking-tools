#!/usr/bin/env bash
#
# GeoKing — affiche les secrets GitHub depuis les sources locales.
#
# Usage :
#   ./scripts/show-secrets.sh           # valeurs en clair (machine locale)
#   ./scripts/show-secrets.sh --redact  # masquées (partageable)
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
gk_project_init
cd "$ROOT"

REDACT=false
[ "${1:-}" = --redact ] && REDACT=true

mask(){
  local v="$1" n="${#1}"
  if [ "$REDACT" = false ] || [ -z "$v" ]; then printf '%s' "$v"; return; fi
  if [ "$n" -le 8 ]; then printf '%s' "****"; return; fi
  printf '%s****%s' "${v:0:4}" "${v: -4}"
}

local_prop(){
  [ -f "$LP" ] || return 0
  grep "^$1=" "$LP" 2>/dev/null | cut -d= -f2- || true
}

cred_prop(){
  [ -f "$CRED" ] || return 0
  grep "^$1=" "$CRED" 2>/dev/null | cut -d= -f2- || true
}

gh_has(){ gh_secret_present "$1" && echo yes || echo no; }

secret_row(){
  local name="$1" source="$2" value="$3" on_gh="$4"
  local mark="non"
  [ "$on_gh" = yes ] && mark="${c_ok}oui${c_off}"
  printf '  %-26s  %sGitHub: %-3s%s  %s%s\n' "$name" "$c_dim" "$mark" "$c_off" "$c_dim" "$source"
  if [ -n "$value" ]; then
    printf '     %s→%s %s%s%s\n' "$c_dim" "$c_off" "$c_bold" "$(mask "$value")" "$c_off"
  else
    printf '     %s→%s %s(absent en local)%s\n' "$c_dim" "$c_off" "$c_dim" "$c_off"
  fi
  blank
}

head_ "🔒  Secrets GitHub — valeurs locales"

if [ "$REDACT" = true ]; then
  warn "Mode --redact : valeurs masquées."
else
  warn "Valeurs en clair — ne pas partager cette sortie."
fi
hint "GitHub ne renvoie jamais le contenu des secrets après enregistrement."
show_link "GitHub Secrets" "$GITHUB_ACTIONS_SECRETS"
blank

subhead "Identifiants app"
secret_row "WEB_CLIENT_ID" "local.properties" "$(local_prop WEB_CLIENT_ID)" "$(gh_has WEB_CLIENT_ID)"
secret_row "GEMINI_API_KEY" "local.properties" "$(local_prop GEMINI_API_KEY)" "$(gh_has GEMINI_API_KEY)"

subhead "Firebase"
if [ -f "$GS" ] && command -v jq >/dev/null 2>&1; then
  GS_SUMMARY="project=$(jq -r '.project_info.project_id' "$GS") package=$(jq -r '.client[0].client_info.android_client_info.package_name' "$GS") ($(wc -c < "$GS" | tr -d ' ') o)"
  secret_row "GOOGLE_SERVICES_JSON" "$GOOGLE_SERVICES_REL" "$GS_SUMMARY" "$(gh_has GOOGLE_SERVICES_JSON)"
elif [ -f "$GS" ]; then
  secret_row "GOOGLE_SERVICES_JSON" "$GOOGLE_SERVICES_REL" "$(wc -c < "$GS" | tr -d ' ') octets" "$(gh_has GOOGLE_SERVICES_JSON)"
else
  secret_row "GOOGLE_SERVICES_JSON" "$GOOGLE_SERVICES_REL" "" "$(gh_has GOOGLE_SERVICES_JSON)"
  show_link "Télécharger" "$FIREBASE_PROJECT"
fi

subhead "Signature Play Store"
if [ -f "$KS_PATH" ]; then
  PASS="$(cred_prop KEYSTORE_PASSWORD)"
  ALIAS="$(cred_prop KEY_ALIAS)"
  SHA1=""
  SHA256=""
  if [ -n "$PASS" ] && [ -n "$ALIAS" ]; then
    SHA1="$(gk_sha1_upload "$PASS")"
    SHA256="$(gk_sha256_upload "$PASS")"
  fi
  secret_row "KEYSTORE_BASE64" "release.keystore" "$(wc -c < "$KS_PATH" | tr -d ' ') o · SHA-1: ${SHA1:-?}" "$(gh_has KEYSTORE_BASE64)"
  [ -n "$SHA256" ] && hint "Upload SHA-256 : ${c_bold}${SHA256}${c_off}"
  hint "SHA App Signing (build distribué par Play, CI) : ./scripts/setup-release.sh verify"
else
  secret_row "KEYSTORE_BASE64" "release.keystore" "" "$(gh_has KEYSTORE_BASE64)"
fi
secret_row "KEYSTORE_PASSWORD" ".keystore-credentials" "$(cred_prop KEYSTORE_PASSWORD)" "$(gh_has KEYSTORE_PASSWORD)"
secret_row "KEY_ALIAS" ".keystore-credentials" "$(cred_prop KEY_ALIAS)" "$(gh_has KEY_ALIAS)"
secret_row "KEY_PASSWORD" ".keystore-credentials" "$(cred_prop KEY_PASSWORD)" "$(gh_has KEY_PASSWORD)"

subhead "Play Console API"
PLAY_JSON=""
for candidate in "$SCRIPTS/.play-service-account.json" "$ROOT"/secrets/*play*.json "$ROOT"/secrets/*service*.json; do
  [ -f "$candidate" ] || continue
  PLAY_JSON="$candidate"
  break
done
if [ -n "$PLAY_JSON" ] && command -v jq >/dev/null 2>&1; then
  PLAY_EMAIL="$(jq -r '.client_email // "?"' "$PLAY_JSON")"
  secret_row "PLAY_SERVICE_ACCOUNT_JSON" "$(basename "$PLAY_JSON")" "client_email=$PLAY_EMAIL" "$(gh_has PLAY_SERVICE_ACCOUNT_JSON)"
else
  secret_row "PLAY_SERVICE_ACCOUNT_JSON" "(JSON local absent)" "(GitHub seulement)" "$(gh_has PLAY_SERVICE_ACCOUNT_JSON)"
fi

subhead "Cloudflare · Worker IA (proxy Gemini)"
secret_row "CLOUDFLARE_API_TOKEN" "local.properties" "$(local_prop CLOUDFLARE_API_TOKEN)" "$(gh_has CLOUDFLARE_API_TOKEN)"
secret_row "CLOUDFLARE_ACCOUNT_ID" "local.properties" "$(local_prop CLOUDFLARE_ACCOUNT_ID)" "$(gh_has CLOUDFLARE_ACCOUNT_ID)"
secret_row "AI_PROXY_URL" "local.properties" "$(local_prop AI_PROXY_URL)" "$(gh_has AI_PROXY_URL)"
hint "GEMINI_API_KEY est aussi un Worker Secret (wrangler) — ./scripts/setup-ai-proxy.sh"

subhead "Secrets enregistrés sur GitHub"
if command -v gh >/dev/null 2>&1; then
  gh secret list 2>/dev/null | while read -r name date time _; do
    [ -n "$name" ] || continue
    printf '  %s•%s %-28s  %s%s %s%s\n' "$c_dim" "$c_off" "$name" "$c_dim" "$date" "$time"
  done || hint "gh non connecté ou aucun secret"
else
  hint "Installer gh :"
  show_url "https://cli.github.com/"
fi

blank
info_box \
  "Pousser vers GitHub : ./scripts/setup-release.sh" \
  "Vérifier OAuth     : ./scripts/setup-release.sh verify"

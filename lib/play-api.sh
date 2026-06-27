#!/usr/bin/env bash
# GeoKing — Play Developer API + synchronisation empreintes Firebase.
set -euo pipefail

[[ -n "${GK_PLAY_API_LOADED:-}" ]] && return 0
GK_PLAY_API_LOADED=1

PLAY_API_SCOPE="https://www.googleapis.com/auth/androidpublisher"
PLAY_API_BASE="https://androidpublisher.googleapis.com/androidpublisher/v3/applications"

gk_b64url() { openssl base64 -e -A | tr '+/' '-_' | tr -d '='; }

gk_sha_strip() {
  printf '%s' "${1//:/}" | tr '[:upper:]' '[:lower:]'
}

gk_sha_format_colons() {
  local h; h="$(gk_sha_strip "$1")"
  local out="" i
  for ((i = 0; i < ${#h}; i += 2)); do
    [ -n "$out" ] && out+=:
    out+="${h:i:2}"
  done
  printf '%s' "$(printf '%s' "$out" | tr '[:lower:]' '[:upper:]')"
}

gk_play_sa_json_path() {
  if [ -n "${PLAY_SERVICE_ACCOUNT_JSON:-}" ] && [ -f "$PLAY_SERVICE_ACCOUNT_JSON" ]; then
    printf '%s' "$PLAY_SERVICE_ACCOUNT_JSON"
    return 0
  fi
  local c
  for c in \
    "$SCRIPTS/.play-service-account.json" \
    "$ROOT/secrets/"*play*.json \
    "$ROOT/secrets/"*service*.json; do
    [ -f "$c" ] || continue
    printf '%s' "$c"
    return 0
  done
  return 1
}

gk_google_sa_access_token() {
  local sa_file="$1"
  local scope="${2:-$PLAY_API_SCOPE}"
  need jq openssl curl

  local client_email private_key pem now exp header payload unsigned sig jwt token
  client_email="$(jq -r '.client_email' "$sa_file")"
  private_key="$(jq -r '.private_key' "$sa_file")"
  [ -n "$client_email" ] && [ "$client_email" != null ] || return 1
  [ -n "$private_key" ] && [ "$private_key" != null ] || return 1

  now="$(date +%s)"
  exp=$((now + 3500))
  pem="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$pem'" RETURN
  printf '%s\n' "$private_key" > "$pem"

  header='{"alg":"RS256","typ":"JWT"}'
  payload="$(jq -nc \
    --arg iss "$client_email" \
    --arg scope "$scope" \
    --argjson iat "$now" \
    --argjson exp "$exp" \
    '{iss:$iss,scope:$scope,aud:"https://oauth2.googleapis.com/token",iat:$iat,exp:$exp}')"

  unsigned="$(printf '%s' "$header" | gk_b64url).$(printf '%s' "$payload" | gk_b64url)"
  sig="$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$pem" | gk_b64url)"
  jwt="${unsigned}.${sig}"

  token="$(curl -fsS -X POST https://oauth2.googleapis.com/token \
    -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}" \
    | jq -r '.access_token // empty')"
  [ -n "$token" ] || return 1
  printf '%s' "$token"
}

gk_play_api() {
  local method="$1" path="$2" token="$3"
  shift 3
  curl -fsS -X "$method" "${PLAY_API_BASE}/${path}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    "$@"
}

gk_play_edit_insert() {
  local token="$1"
  gk_play_api POST "${APP_ID}/edits" "$token" | jq -r '.id // empty'
}

gk_play_edit_delete() {
  local token="$1" edit="$2"
  gk_play_api DELETE "${APP_ID}/edits/${edit}" "$token" >/dev/null 2>&1 || true
}

gk_play_latest_version_code() {
  local token="$1"
  need jq
  local edit tracks track json codes
  edit="$(gk_play_edit_insert "$token")"
  [ -n "$edit" ] || return 1
  codes=""
  for track in internal alpha beta production; do
    json="$(gk_play_api GET "${APP_ID}/edits/${edit}/tracks/${track}" "$token" 2>/dev/null || true)"
    [ -n "$json" ] || continue
    while IFS= read -r vc; do
      [ -n "$vc" ] || continue
      codes="${codes}${vc}"$'\n'
    done < <(printf '%s' "$json" | jq -r '.releases[]?.versionCodes[]? // empty' 2>/dev/null)
  done
  gk_play_edit_delete "$token" "$edit"
  [ -n "$codes" ] || return 1
  printf '%s' "$codes" | awk 'NF { if ($1 > max) max = $1 } END { if (max) print max }'
}

gk_play_generated_apks_json() {
  local token="$1" version_code="$2"
  gk_play_api GET "${APP_ID}/generatedApks/list?versionCode=${version_code}" "$token"
}

gk_play_universal_apk_download_id() {
  local json="$1"
  jq -r '
    .generatedApks[]?
    | select(.generatedUniversalApk.downloadId != null)
    | .generatedUniversalApk.downloadId
    | select(. != "")
    ' <<<"$json" | head -1
}

gk_play_download_universal_apk() {
  local token="$1" version_code="$2" download_id="$3" dest="$4"
  curl -fsS \
    "${PLAY_API_BASE}/${APP_ID}/generatedApks/download/${version_code}/${download_id}" \
    -H "Authorization: Bearer ${token}" \
    -o "$dest"
}

gk_sha1_from_apk() {
  local apk="$1"
  need keytool
  keytool -printcert -jarfile "$apk" 2>/dev/null \
    | awk -F'SHA1: ' '/SHA1:/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}'
}

gk_sha256_from_apk() {
  local apk="$1"
  need keytool
  keytool -printcert -jarfile "$apk" 2>/dev/null \
    | awk -F'SHA256: ' '/SHA256:/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}'
}

gk_play_app_signing_sha1() {
  local token="${1:-}"
  local version_code="${2:-}"
  local sa_file apk_json download_id tmp_apk sha1

  if [ -z "$token" ]; then
    sa_file="$(gk_play_sa_json_path)" || return 1
    token="$(gk_google_sa_access_token "$sa_file")" || return 1
  fi

  if [ -z "$version_code" ]; then
    version_code="$(gk_play_latest_version_code "$token")" || return 1
  fi

  apk_json="$(gk_play_generated_apks_json "$token" "$version_code")" || return 1
  download_id="$(gk_play_universal_apk_download_id "$apk_json")"
  [ -n "$download_id" ] || return 1

  tmp_apk="$(mktemp "${TMPDIR:-/tmp}/geoking-play-XXXXXX.apk")"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_apk'" RETURN
  gk_play_download_universal_apk "$token" "$version_code" "$download_id" "$tmp_apk"
  sha1="$(gk_sha1_from_apk "$tmp_apk")"
  [ -n "$sha1" ] || return 1
  gk_sha_format_colons "$sha1"
}

# Download the Play App Signing universal APK once and print both fingerprints,
# colon-formatted, on a single line: "<SHA-1> <SHA-256>". Empty on failure.
gk_play_app_signing_fps() {
  local token="${1:-}" version_code="${2:-}"
  local sa_file apk_json download_id tmp_apk sha1 sha256

  if [ -z "$token" ]; then
    sa_file="$(gk_play_sa_json_path)" || return 1
    token="$(gk_google_sa_access_token "$sa_file")" || return 1
  fi
  if [ -z "$version_code" ]; then
    version_code="$(gk_play_latest_version_code "$token")" || return 1
  fi
  apk_json="$(gk_play_generated_apks_json "$token" "$version_code")" || return 1
  download_id="$(gk_play_universal_apk_download_id "$apk_json")"
  [ -n "$download_id" ] || return 1

  tmp_apk="$(mktemp "${TMPDIR:-/tmp}/geoking-play-XXXXXX.apk")"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_apk'" RETURN
  gk_play_download_universal_apk "$token" "$version_code" "$download_id" "$tmp_apk"
  sha1="$(gk_sha1_from_apk "$tmp_apk")"
  sha256="$(gk_sha256_from_apk "$tmp_apk")"
  [ -n "$sha1" ] || return 1
  printf '%s %s' "$(gk_sha_format_colons "$sha1")" "$(gk_sha_format_colons "$sha256")"
}

gk_play_app_signing_sha256() {
  local fps; fps="$(gk_play_app_signing_fps "$@")" || return 1
  printf '%s' "${fps#* }"
}

gk_firebase_android_app_id() {
  if [ -n "${FIREBASE_ANDROID_APP_ID:-}" ] && [ "$FIREBASE_ANDROID_APP_ID" != null ]; then
    printf '%s' "$FIREBASE_ANDROID_APP_ID"
    return 0
  fi
  if [ -f "$GS" ] && command -v jq >/dev/null 2>&1; then
    jq -r '.client[0].client_info.mobilesdk_app_id // empty' "$GS"
    return 0
  fi
  return 1
}

# Android Firebase app ID: manifest → existing google-services.json → live `apps:list`.
gk_firebase_android_app_id_resolve() {
  local id
  id="$(gk_firebase_android_app_id 2>/dev/null || true)"
  if [ -n "$id" ] && [ "$id" != null ]; then printf '%s' "$id"; return 0; fi
  gk_firebase_cli_ready || return 1
  firebase apps:list ANDROID --project "$PROJECT_ID" 2>/dev/null \
    | grep -oiE '1:[0-9]+:android:[0-9a-f]+' | head -1
}

# Web OAuth client (client_type 3) from a google-services.json (defaults to $GS).
gk_web_client_id_from_gs() {
  local f="${1:-$GS}"
  [ -f "$f" ] && command -v jq >/dev/null 2>&1 || return 1
  jq -r '.client[0].oauth_client[]? | select(.client_type == 3) | .client_id' "$f" \
    | grep -m1 '.'
}

gk_firebase_cli_ready() {
  local list
  command -v firebase >/dev/null 2>&1 || return 1
  list="$(firebase login:list 2>/dev/null)" || return 1
  printf '%s' "$list" | grep -q 'No logged in users' && return 1
  printf '%s' "$list" | grep -q '@'
}

gk_firebase_sha_list_raw() {
  local app_id="$1"
  firebase apps:android:sha:list "$app_id" --project "$PROJECT_ID" 2>/dev/null
}

gk_firebase_sha_known() {
  local needle; needle="$(gk_sha_strip "$1")"
  local app_id out h
  app_id="$(gk_firebase_android_app_id)" || return 1
  gk_firebase_cli_ready || return 1
  out="$(gk_firebase_sha_list_raw "$app_id")" || return 1
  while IFS= read -r h; do
    [ "$(gk_sha_strip "$h")" = "$needle" ] && return 0
  done < <(printf '%s' "$out" | grep -oiE '[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){19}|[0-9A-Fa-f]{40}')
  return 1
}

gk_firebase_sha_create() {
  local sha1="$1"
  local app_id hash
  app_id="$(gk_firebase_android_app_id)" || return 1
  gk_firebase_cli_ready || return 1
  hash="$(gk_sha_strip "$sha1")"
  firebase apps:android:sha:create "$app_id" "$hash" --project "$PROJECT_ID" >/dev/null
}

gk_firebase_sha_ensure() {
  local sha1="$2"
  local label="$1"
  [ -n "$sha1" ] || return 1
  sha1="$(gk_sha_format_colons "$sha1")"
  if gk_firebase_sha_known "$sha1"; then
    ok "Firebase · $label déjà enregistré — ${c_bold}${sha1}${c_off}"
    return 0
  fi
  if gk_firebase_sha_create "$sha1"; then
    ok "Firebase · $label ajouté — ${c_bold}${sha1}${c_off}"
    return 0
  fi
  return 1
}

gk_sync_local_sha_to_firebase() {
  local label="$1" sha1="$2"
  [ -n "$sha1" ] || return 1
  if ! gk_firebase_cli_ready; then
    hint "Firebase CLI : ${c_bold}firebase login${c_off} pour enregistrer $label automatiquement"
    hint "SHA-1 $label : ${c_bold}$(gk_sha_format_colons "$sha1")${c_off}"
    return 1
  fi
  gk_firebase_sha_ensure "$label" "$sha1"
}

# Affiché quand l'API Play ne peut pas fournir le SHA-1 App Signing (②).
gk_hint_play_sha_manual_fallback() {
  local reason="${1:-}"
  [ -n "$reason" ] && hint "$reason"
  hint "Repli manuel :"
  hint "  1. Play Console → Intégrité → Play app signing"
  hint "  2. Section « App signing key certificate » → copier le SHA-1"
  hint "  3. Firebase → Paramètres → ton app Android → Ajouter une empreinte"
  show_link "Ouvrir Play · App signing" "$PLAY_APP_INTEGRITY"
}

gk_sync_play_app_signing_sha() {
  local sha1 sa_file interactive="${GK_SHA_SYNC_INTERACTIVE:-true}"

  subhead "② Play App Signing — SHA-1 via API Play Developer"
  if ! sa_file="$(gk_play_sa_json_path)"; then
    warn "Compte de service Play absent — lecture API impossible"
    hint "Auto : ./scripts/setup-release.sh play"
    hint "      → enregistre scripts/.play-service-account.json (gitignored)"
    gk_hint_play_sha_manual_fallback
    return 1
  fi

  if ! sha1="$(gk_play_app_signing_sha1)"; then
    warn "API Play : échec de lecture du SHA-1 App Signing"
    hint "Vérifie : release déjà publiée sur Play (AAB signé par Google)"
    hint "         compte de service invité avec droit « Gestionnaire de releases »"
    gk_hint_play_sha_manual_fallback
    return 1
  fi

  ok "SHA-1 App Signing (②) : ${c_bold}${sha1}${c_off}"
  gk_sync_local_sha_to_firebase "Play App Signing ②" "$sha1" || true

  if [ "$interactive" = true ] && gk_firebase_cli_ready \
     && confirm "Télécharger google-services.json mis à jour ?"; then
    local app_id
    app_id="$(gk_firebase_android_app_id)" || die "firebaseAndroidAppId manquant dans project.manifest.json"
    need firebase
    firebase apps:sdkconfig ANDROID "$app_id" --project "$PROJECT_ID" > "$GS"
    ok "google-services.json mis à jour → $GOOGLE_SERVICES_REL"
    if command -v gh >/dev/null 2>&1 && confirm "Pousser GOOGLE_SERVICES_JSON sur GitHub ?"; then
      gk_push_google_services_secret
    fi
  fi
  return 0
}

gk_sync_all_sha_fingerprints() {
  local d u
  subhead "Synchronisation empreintes → Firebase"
  if ! gk_firebase_cli_ready; then
    warn "firebase login requis pour la synchro automatique"
    show_url "https://firebase.google.com/docs/cli#install-cli"
  fi

  d="$(gk_sha1_debug)"
  [ -n "$d" ] && gk_sync_local_sha_to_firebase "Debug ①" "$d" || true

  u="$(gk_sha1_upload)"
  [ -n "$u" ] && gk_sync_local_sha_to_firebase "Upload ③" "$u" || true

  gk_sync_play_app_signing_sha || true
}

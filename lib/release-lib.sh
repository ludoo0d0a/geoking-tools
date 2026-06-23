#!/usr/bin/env bash
# GeoKing — shared release / OAuth helpers (setup-release, verify-oauth, show-secrets).
set -euo pipefail

[[ -n "${GK_LIB_LOADED:-}" ]] && return 0
GK_LIB_LOADED=1

# shellcheck source=ui.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh"
# shellcheck source=play-api.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/play-api.sh"

gk_lib_init() {
  ROOT="$1"
  SCRIPTS="$ROOT/scripts"
  GS="$ROOT/${GOOGLE_SERVICES_REL:-composeApp/google-services.json}"
  LP="$ROOT/local.properties"
  KS_PATH="$ROOT/release.keystore"
  CRED="$SCRIPTS/.keystore-credentials"
  ALIAS="${KEY_ALIAS:-key0}"
}

gk_sha1_debug() {
  keytool -list -v -keystore "$HOME/.android/debug.keystore" -alias androiddebugkey \
    -storepass android -keypass android 2>/dev/null \
    | awk -F'SHA1: ' '/SHA1:/{print $2; exit}'
}

gk_sha1_upload() {
  local pass="${1:-}"
  [ -n "$pass" ] || { [ -f "$CRED" ] && pass="$(grep '^KEYSTORE_PASSWORD=' "$CRED" | cut -d= -f2-)"; }
  [ -n "$pass" ] && [ -f "$KS_PATH" ] || return 0
  keytool -list -v -keystore "$KS_PATH" -alias "$ALIAS" -storepass "$pass" 2>/dev/null \
    | awk -F'SHA1: ' '/SHA1:/{print $2; exit}'
}

gk_print_sha1_guide() {
  subhead "Empreintes SHA-1  ·  package $APP_ID"
  info_box \
    "Google autorise le sign-in seulement si le certificat qui a signé" \
    "l'APK installé est enregistré dans Firebase ou Google Cloud."
  blank
  hint "Où enregistrer les empreintes :"
  show_link "Firebase" "$FIREBASE_PROJECT"
  show_link "Google Cloud" "$GCP_CREDENTIALS"
  blank

  local d; d="$(gk_sha1_debug)"
  printf '  %s① DEBUG%s  %sAndroid Studio · Run / installDebug%s\n' "$c_bold" "$c_off" "$c_dim" "$c_off"
  if [ -n "$d" ]; then hint "SHA-1 : ${c_bold}${d}${c_off}"
  else warn "~/.android/debug.keystore absent — lance l'app une fois dans Android Studio"
  fi
  hint "Si le sign-in échoue en local uniquement."
  blank

  printf '  %s② PLAY APP SIGNING%s  %s⚡ obligatoire Play Store%s\n' "$c_bold" "$c_off" "$c_warn" "$c_off"
  local p=""
  if sa_file="$(gk_play_sa_json_path 2>/dev/null)"; then
    p="$(gk_play_app_signing_sha1 2>/dev/null || true)"
  fi
  if [ -n "$p" ]; then
    hint "SHA-1 (API Play) : ${c_bold}${p}${c_off}"
    if gk_firebase_cli_ready && gk_firebase_sha_known "$p" 2>/dev/null; then
      ok "Enregistré dans Firebase"
    elif gk_firebase_cli_ready; then
      warn "Absent de Firebase — ./scripts/setup-release.sh play-sha"
    fi
  else
    hint "Auto : ./scripts/setup-release.sh play-sha (après 1ʳᵉ release Play)"
    hint "Manuel : Play Console → App signing key certificate → Firebase"
  fi
  show_link "Play · App signing" "$PLAY_APP_INTEGRITY"
  show_link "Dashboard" "$PLAY_APP_DASHBOARD"
  show_link "Guide Google" "$PLAY_INTEGRITY_HELP"
  hint "Pas la clé d'upload — Google re-signe l'APK avant distribution."
  blank

  local u; u="$(gk_sha1_upload)"
  printf '  %s③ UPLOAD KEY%s  %soptionnel · sideload release%s\n' "$c_bold" "$c_off" "$c_dim" "$c_off"
  if [ -n "$u" ]; then hint "SHA-1 : ${c_bold}${u}${c_off}"
  else hint "Généré par : ./scripts/setup-release.sh keystore"
  fi
  blank
  info_box "Résumé : debug Studio → ①  |  Play Store → ②  |  les deux → ① + ②"
}

gk_print_console_checklist() {
  subhead "Consoles utiles"
  show_link "GCP" "$GCP_CONSOLE"
  show_link "OAuth" "$GCP_CREDENTIALS"
  show_link "Consentement" "$GCP_OAUTH_CONSENT"
  show_link "Firebase" "$FIREBASE_CONSOLE"
  show_link "Auth Google" "$FIREBASE_AUTH_GOOGLE"
  show_link "Users" "$FIREBASE_AUTH_USERS"
  show_link "Empreintes" "$FIREBASE_PROJECT"
  show_link "Play Console" "$PLAY_APP_DASHBOARD"
  blank
}

gk_print_logcat_help() {
  subhead "Test sur appareil"
  code "adb logcat -c && adb logcat -s ${SIGN_IN_LOG_TAG:-AppSignIn}"
  hint "Puis appuyer sur « Continuer avec Google » dans l'app."
  blank
  hint "Messages fréquents :"
  printf '     %s•%s WEB_CLIENT_ID is blank       → secret CI ou google-services.json manquant\n' "$c_dim" "$c_off"
  printf '     %s•%s signInWithCredential:failure → Google désactivé dans Firebase Auth\n' "$c_dim" "$c_off"
  printf '     %s•%s Caller not whitelisted / 16  → empreinte SHA-1 ① ou ② manquante\n' "$c_dim" "$c_off"
  blank
}

gk_adb_status() {
  command -v adb >/dev/null 2>&1 && adb get-state >/dev/null 2>&1 || return 0
  subhead "Appareil USB connecté"
  if adb shell pm path "$APP_ID" >/dev/null 2>&1; then
    ok "$APP_ID installé sur l'appareil"
    code "adb shell pm dump $APP_ID | grep -A2 signatures"
  else
    warn "$APP_ID non installé sur l'appareil"
  fi
  blank
}

gh_secret_present() {
  command -v gh >/dev/null 2>&1 && gh secret list 2>/dev/null | awk '{print $1}' | grep -qx "$1"
}

gk_check_google_services() {
  if [ ! -f "$GS" ]; then
    fail "${GOOGLE_SERVICES_REL:-composeApp/google-services.json} manquant"
    hint "Place le fichier ici : $GS"
    show_link "Télécharger" "$FIREBASE_PROJECT"
    return 1
  fi
  ok "$GOOGLE_SERVICES_REL présent"
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq absent — package Android non vérifié"
    return 0
  fi
  local pkg
  pkg="$(jq -r '.client[0].client_info.android_client_info.package_name' "$GS")"
  if [ "$pkg" = "$APP_ID" ]; then
    ok "Package $APP_ID dans google-services.json"
  else
    fail "Package « $pkg » ≠ « $APP_ID » attendu"
    return 1
  fi
  return 0
}

gk_require_google_services() {
  if ! gk_check_google_services; then
    blank
    die "Fichier requis : $GS"
  fi
}

gk_push_google_services_secret() {
  need gh
  gk_require_google_services
  base64 < "$GS" | tr -d '\n' | gh secret set GOOGLE_SERVICES_JSON
  ok "Secret GitHub GOOGLE_SERVICES_JSON enregistré"
}

gk_check_web_client_id() {
  if [ ! -f "$LP" ] || ! grep -q '^WEB_CLIENT_ID=' "$LP"; then
    fail "WEB_CLIENT_ID manquant dans local.properties"
    return 1
  fi
  local web
  web="$(grep '^WEB_CLIENT_ID=' "$LP" | cut -d= -f2-)"
  if [ -z "$web" ]; then
    fail "WEB_CLIENT_ID vide dans local.properties"
    return 1
  fi
  if echo "$web" | grep -qE '^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$'; then
    ok "WEB_CLIENT_ID — format client Web OK (…${web##*-})"
  else
    fail "WEB_CLIENT_ID — format invalide (attendu …apps.googleusercontent.com)"
    return 1
  fi
  return 0
}

gk_check_ci_web_client_id() {
  local workflow="$ROOT/.github/workflows/release-play.yml"
  if grep -q 'WEB_CLIENT_ID: \${{ secrets.WEB_CLIENT_ID }}' "$workflow" 2>/dev/null; then
    ok "Workflow release-play.yml injecte WEB_CLIENT_ID"
  elif grep -q 'geoking-ci/.github/workflows/release-play.yml' "$workflow" 2>/dev/null \
       && grep -q 'secrets: inherit' "$workflow" 2>/dev/null; then
    ok "Workflow release-play.yml délègue à geoking-ci (secrets: inherit → WEB_CLIENT_ID)"
  else
    fail "release-play.yml n'injecte PAS WEB_CLIENT_ID"
    return 1
  fi
  if git show origin/main:.github/workflows/release-play.yml 2>/dev/null | grep -qE 'WEB_CLIENT_ID|geoking-ci/.github/workflows/release-play'; then
    ok "origin/main contient la config release Play"
  else
    warn "origin/main sans config release à jour — build Play actuel peut être cassé"
  fi
  return 0
}

gk_verify_oauth() {
  head_ "🔐  Vérification Google Sign-In / Firebase Auth"

  subhead "Firebase"
  gk_check_google_services || true
  if gh_secret_present GOOGLE_SERVICES_JSON; then ok "Secret GitHub GOOGLE_SERVICES_JSON"
  else warn "Secret GOOGLE_SERVICES_JSON absent (CI)"; fi

  subhead "OAuth · WEB_CLIENT_ID"
  gk_check_web_client_id || true
  if gh_secret_present WEB_CLIENT_ID; then ok "Secret GitHub WEB_CLIENT_ID"
  else warn "Secret WEB_CLIENT_ID absent ou gh non connecté"; fi

  subhead "CI GitHub Actions"
  gk_check_ci_web_client_id || true

  GK_SHA_SYNC_INTERACTIVE=false
  gk_sync_all_sha_fingerprints

  gk_print_sha1_guide
  gk_print_console_checklist
  gk_print_logcat_help
  gk_adb_status
}

set_local_prop() {
  local key="$1" val="$2" f="$LP"
  touch "$f"
  if grep -q "^$key=" "$f"; then sedi -E "s#^$key=.*#$key=$val#" "$f"
  else printf '%s=%s\n' "$key" "$val" >> "$f"; fi
  ok "$key → local.properties"
}

#!/usr/bin/env bash
#
# GeoKing — assistant de configuration release (première fois ou reprise).
#
# Usage (via le wrapper scripts/ du projet) :
#   ./scripts/setup-release.sh [all|keystore|play|firebase|oauth|gemini|secrets|verify]
#
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
geoking_project_init
cd "$ROOT"

# ---- étape 1 : keystore ----------------------------------------------------
step_keystore(){
  head_ "🔑  1 · Keystore de signature"
  info_box \
    "Signe l'AAB publié sur le Play Store par GitHub Actions." \
    "Secrets : KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD"
  show_link "GitHub Secrets" "$GITHUB_ACTIONS_SECRETS"
  blank
  need keytool; need gh; need openssl; need base64
  local PASS
  if [ -f "$KS_PATH" ] && [ -f "$CRED" ]; then
    ok "Keystore existant : release.keystore"
    if confirm "Réutiliser (re-pousser les secrets GitHub) ?"; then
      PASS="$(grep '^KEYSTORE_PASSWORD=' "$CRED" | cut -d= -f2-)"
    elif confirm "Régénérer ? ATTENTION : change la signature (avant 1ère publication Play) !"; then
      rm -f "$KS_PATH"; PASS=""
    else
      hint "Étape ignorée."; return
    fi
  fi
  if [ ! -f "$KS_PATH" ]; then
    PASS="$(openssl rand -base64 48 | LC_ALL=C tr -dc 'A-Za-z0-9')"; PASS="${PASS:0:28}"
    say "  Génération de release.keystore …"
    keytool -genkeypair -v -keystore "$KS_PATH" -alias "$ALIAS" \
      -keyalg RSA -keysize 2048 -validity 10000 -storepass "$PASS" -keypass "$PASS" \
      -dname "$KEYSTORE_DN" >/dev/null
    umask 077
    { echo "# NE PAS COMMITER — généré $(date -u +%FT%TZ)"
      echo "KEYSTORE_PASSWORD=$PASS"; echo "KEY_ALIAS=$ALIAS"; echo "KEY_PASSWORD=$PASS"; } > "$CRED"
    chmod 600 "$CRED"
    ok "Keystore créé → scripts/.keystore-credentials"
  fi
  local B64; B64="$(base64 < "$KS_PATH" | tr -d '\n')"
  printf '%s' "$B64"   | gh secret set KEYSTORE_BASE64
  printf '%s' "$PASS"  | gh secret set KEYSTORE_PASSWORD
  printf '%s' "$ALIAS" | gh secret set KEY_ALIAS
  printf '%s' "$PASS"  | gh secret set KEY_PASSWORD
  ok "Secrets KEYSTORE_* mis à jour sur GitHub"
  local s; s="$(geoking_sha1_upload "$PASS")"
  [ -n "$s" ] && hint "SHA-1 upload (③) : ${c_bold}${s}${c_off}"
}

# ---- étape 2 : compte de service Play --------------------------------------
step_play(){
  head_ "📦  2 · Compte de service Google Play"
  info_box "Permet à la CI d'uploader l'AAB sans intervention manuelle." \
           "Secret : PLAY_SERVICE_ACCOUNT_JSON"
  blank
  need gh
  step "Activer l'API Play Android Developer ($PROJECT_ID)"
  show_url "$GCP_PLAY_API"
  step "Créer un compte de service (Clés → JSON)"
  show_url "$GCP_SERVICE_ACCOUNTS"
  step "Play Console → Utilisateurs → Gestionnaire de releases"
  show_url "$PLAY_APP_DASHBOARD"
  blank
  local p; p="$(ask "Chemin du JSON téléchargé (Entrée pour passer)")"
  if [ -n "$p" ]; then
    p="${p/#\~/$HOME}"
    [ -f "$p" ] || { warn "Fichier introuvable : $p"; return; }
    gh secret set PLAY_SERVICE_ACCOUNT_JSON < "$p"
    ok "Secret PLAY_SERVICE_ACCOUNT_JSON enregistré"
  else
    hint "Plus tard : gh secret set PLAY_SERVICE_ACCOUNT_JSON < fichier.json"
  fi
}

# ---- étape 3 : Firebase Auth -----------------------------------------------
step_firebase(){
  head_ "🔥  3 · Firebase Auth"
  info_box \
    "Connexion Google via Firebase Authentication." \
    "Fichier requis : $GOOGLE_SERVICES_REL (gitignored)" \
    "Projet $PROJECT_ID · package $APP_ID"
  show_link "Users connectés" "$FIREBASE_AUTH_USERS"
  blank
  step "Télécharger google-services.json → placer dans le chemin ci-dessus"
  show_url "$FIREBASE_PROJECT"
  step "Activer le fournisseur Google dans Authentication"
  show_url "$FIREBASE_AUTH_GOOGLE"
  step "Enregistrer les empreintes SHA-1"
  geoking_print_sha1_guide
  geoking_push_google_services_secret
}

# ---- étape 4 : OAuth -------------------------------------------------------
step_oauth(){
  head_ "🌐  4 · Connexion Google — OAuth"
  info_box "Vérifie Google Cloud ($PROJECT_ID) après l'étape Firebase."
  geoking_print_sha1_guide
  step "Écran de consentement OAuth"
  show_url "$GCP_OAUTH_CONSENT"
  step "Identifiants OAuth (clients Android + Web)"
  show_url "$GCP_CREDENTIALS"
  hint "Client Android : $APP_ID + empreintes ① / ②"
  hint "Client Web : ID = WEB_CLIENT_ID ${c_warn}(≠ client Android)${c_off}"
  blank
  local id; id="$(ask "ID client Web (…apps.googleusercontent.com, Entrée pour passer)")"
  if [ -n "$id" ]; then
    set_local_prop WEB_CLIENT_ID "$id"
    need gh
    printf '%s' "$id" | gh secret set WEB_CLIENT_ID
    ok "Secret WEB_CLIENT_ID enregistré"
  else hint "Ignoré."; fi
}

# ---- étape 5 : Gemini ------------------------------------------------------
step_gemini(){
  head_ "✨  5 · Clé API Gemini"
  info_box "IA : reconnaissance étiquette, prix estimé, accords mets-vins." \
           "Secret : GEMINI_API_KEY"
  show_url "$GEMINI_API_KEYS"
  blank
  local k; k="$(ask "Clé Gemini (Entrée pour passer)")"
  if [ -n "$k" ]; then
    set_local_prop GEMINI_API_KEY "$k"
    need gh
    printf '%s' "$k" | gh secret set GEMINI_API_KEY
    ok "Secret GEMINI_API_KEY enregistré"
  else hint "Ignoré."; fi
}

# ---- menu ------------------------------------------------------------------
case "${1:-all}" in
  keystore) step_keystore ;;
  play)     step_play ;;
  firebase) step_firebase ;;
  oauth)    step_oauth ;;
  gemini)   step_gemini ;;
  secrets)  "$GEOKING_TOOLS/bin/show-secrets.sh" ;;
  verify)   geoking_verify_oauth ;;
  all)
    head_ "🍷  Configuration release · $PROJECT_NAME"
    info_box \
      "Projet : $PROJECT_ID" \
      "Manifest : scripts/project.manifest.json"
    show_link "Play Console" "$PLAY_APP_DASHBOARD"
    blank
    step_keystore; step_play; step_firebase; step_oauth; step_gemini
    ;;
  *)
    say "Usage : setup-release.sh [all|keystore|play|firebase|oauth|gemini|secrets|verify]"
    exit 2
    ;;
esac

case "${1:-all}" in
  secrets|verify) exit 0 ;;
esac

head_ "✅  Terminé"
"$GEOKING_TOOLS/bin/show-secrets.sh"
blank
info_box \
  "Prochaine étape : push sur main ou tag v* → CI → piste internal Play Store." \
  "Vérifier OAuth : ./scripts/setup-release.sh verify"
show_link "Play Console" "$PLAY_APP_DASHBOARD"

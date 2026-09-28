#!/usr/bin/env bash
#
# GeoKing — vérifie le mot de passe du keystore d'upload Play.
#
# Usage (depuis une app via le wrapper) :
#   ./scripts/check-keystore-password.sh
#   KEY_STORE_PASSWORD='…' ./scripts/check-keystore-password.sh
#   ./scripts/check-keystore-password.sh /path/to.keystore
#
# Résout, dans l'ordre :
#   keystore  → arg1 | KEYSTORE_FILE | release.keystore | *-app.keystore
#   password  → KEYSTORE_PASSWORD | KEY_STORE_PASSWORD | local.properties |
#               scripts/.keystore-credentials | prompt
#   alias     → KEY_ALIAS | ALIAS | local.properties | credentials | manifest
#
# Si OK : propose d'enregistrer KEYSTORE_* dans local.properties (+ credentials).
#
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
gk_project_init
cd "$ROOT"

need keytool

local_prop() {
  [ -f "$LP" ] || return 0
  grep "^$1=" "$LP" 2>/dev/null | cut -d= -f2- || true
}

cred_prop() {
  [ -f "$CRED" ] || return 0
  grep "^$1=" "$CRED" 2>/dev/null | cut -d= -f2- || true
}

resolve_keystore() {
  if [ -n "${1:-}" ]; then
    [ -f "$1" ] || die "Keystore introuvable : $1"
    printf '%s' "$1"
    return 0
  fi
  if [ -n "${KEYSTORE_FILE:-}" ] && [ -f "$KEYSTORE_FILE" ]; then
    printf '%s' "$KEYSTORE_FILE"
    return 0
  fi
  local from_lp=""
  from_lp="$(local_prop KEYSTORE_FILE)"
  if [ -n "$from_lp" ] && [ -f "$from_lp" ]; then
    printf '%s' "$from_lp"
    return 0
  fi
  if [ -f "$KS_PATH" ]; then
    printf '%s' "$KS_PATH"
    return 0
  fi
  local cand
  for cand in "$ROOT"/*-app.keystore; do
    [ -f "$cand" ] || continue
    printf '%s' "$cand"
    return 0
  done
  return 1
}

write_credentials() {
  local pass="$1" alias="$2" key_pass="${3:-$1}"
  umask 077
  {
    echo "# NE PAS COMMITER — généré $(date -u +%FT%TZ) par check-keystore-password"
    echo "KEYSTORE_PASSWORD=$pass"
    echo "KEY_ALIAS=$alias"
    echo "KEY_PASSWORD=$key_pass"
  } > "$CRED"
  chmod 600 "$CRED"
  ok "Credentials → scripts/.keystore-credentials (gitignored)"
}

head_ "🔑  Vérification mot de passe keystore"

KS="$(resolve_keystore "${1:-}")" \
  || die "Keystore introuvable (release.keystore ou *-app.keystore). Lance ./scripts/setup-release.sh keystore"

ok "Keystore : $KS"

PASS="${KEYSTORE_PASSWORD:-${KEY_STORE_PASSWORD:-}}"
[ -z "$PASS" ] && PASS="$(local_prop KEYSTORE_PASSWORD)"
[ -z "$PASS" ] && PASS="$(local_prop KEY_STORE_PASSWORD)"
[ -z "$PASS" ] && PASS="$(cred_prop KEYSTORE_PASSWORD)"
if [ -z "$PASS" ]; then
  PASS="$(ask "KEYSTORE_PASSWORD (Entrée pour annuler)")"
fi
[ -n "$PASS" ] || die "Mot de passe manquant (exporte KEY_STORE_PASSWORD ou KEYSTORE_PASSWORD)."

ALIAS_USE="${KEY_ALIAS:-${ALIAS:-}}"
[ -z "$ALIAS_USE" ] && ALIAS_USE="$(local_prop KEY_ALIAS)"
[ -z "$ALIAS_USE" ] && ALIAS_USE="$(local_prop ALIAS)"
[ -z "$ALIAS_USE" ] && ALIAS_USE="$(cred_prop KEY_ALIAS)"
[ -z "$ALIAS_USE" ] && ALIAS_USE="key0"

KEY_PASS="${KEY_PASSWORD:-}"
[ -z "$KEY_PASS" ] && KEY_PASS="$(local_prop KEY_PASSWORD)"
[ -z "$KEY_PASS" ] && KEY_PASS="$(cred_prop KEY_PASSWORD)"
[ -z "$KEY_PASS" ] && KEY_PASS="$PASS"

blank
hint "alias = ${c_bold}${ALIAS_USE}${c_off}"
echo "${c_dim}→ keytool -list -v …${c_off}"

OUT="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$OUT'" EXIT

if ! keytool -list -v -keystore "$KS" -alias "$ALIAS_USE" -storepass "$PASS" >"$OUT" 2>&1; then
  blank
  if grep -qiE 'password was incorrect|Keystore was tampered' "$OUT"; then
    die "Mot de passe incorrect (ou keystore corrompu)."
  fi
  if grep -qiE 'Alias .+ does not exist|alias .+ not found' "$OUT"; then
    warn "Alias introuvable : $ALIAS_USE"
    hint "Alias présents :"
    keytool -list -keystore "$KS" -storepass "$PASS" 2>/dev/null | sed 's/^/     /' || true
    die "Corrige ALIAS / KEY_ALIAS puis relance."
  fi
  cat "$OUT" >&2
  die "keytool a échoué."
fi

SHA1="$(awk -F'SHA1: ' '/SHA1:/{print $2; exit}' "$OUT")"
SHA256="$(awk -F'SHA256: ' '/SHA256:/{print $2; exit}' "$OUT")"

blank
ok "Mot de passe OK"
[ -n "$SHA1" ] && hint "SHA-1   : ${c_bold}${SHA1}${c_off}"
[ -n "$SHA256" ] && hint "SHA-256 : ${c_bold}${SHA256}${c_off}"
blank

if confirm "Sauver KEYSTORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD dans local.properties ?"; then
  set_local_prop KEYSTORE_FILE "$KS"
  set_local_prop KEYSTORE_PASSWORD "$PASS"
  set_local_prop KEY_ALIAS "$ALIAS_USE"
  set_local_prop KEY_PASSWORD "$KEY_PASS"
  # Alias legacy (mêmes valeurs) pour scripts / CI Gaston historiques
  set_local_prop KEY_STORE_PASSWORD "$PASS"
  set_local_prop ALIAS "$ALIAS_USE"
  write_credentials "$PASS" "$ALIAS_USE" "$KEY_PASS"
  blank
  hint "local.properties est gitignored — ne pas le committer."
else
  hint "Ignoré. Pour build-and-publish :"
  code "export KEY_STORE_PASSWORD='…'"
  code "export KEY_PASSWORD=\"\$KEY_STORE_PASSWORD\""
  code "export ALIAS=$ALIAS_USE"
fi

blank
hint "Ensuite :"
code "./scripts/build-and-publish.sh -y --track internal"

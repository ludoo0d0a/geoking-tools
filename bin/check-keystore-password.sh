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
#   password  → KEYSTORE_PASSWORD | KEY_STORE_PASSWORD | scripts/.keystore-credentials | prompt
#   alias     → KEY_ALIAS | ALIAS | manifest keystoreAlias | prompt (défaut key0)
#
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
gk_project_init
cd "$ROOT"

need keytool

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

cred_prop() {
  [ -f "$CRED" ] || return 0
  grep "^$1=" "$CRED" 2>/dev/null | cut -d= -f2- || true
}

head_ "🔑  Vérification mot de passe keystore"

KS="$(resolve_keystore "${1:-}")" \
  || die "Keystore introuvable (release.keystore ou *-app.keystore). Lance ./scripts/setup-release.sh keystore"

ok "Keystore : $KS"

PASS="${KEYSTORE_PASSWORD:-${KEY_STORE_PASSWORD:-}}"
[ -z "$PASS" ] && PASS="$(cred_prop KEYSTORE_PASSWORD)"
if [ -z "$PASS" ]; then
  PASS="$(ask "KEYSTORE_PASSWORD (Entrée pour annuler)")"
fi
[ -n "$PASS" ] || die "Mot de passe manquant (exporte KEY_STORE_PASSWORD ou KEYSTORE_PASSWORD)."

ALIAS_USE="${KEY_ALIAS:-${ALIAS:-}}"
[ -z "$ALIAS_USE" ] && ALIAS_USE="$(cred_prop KEY_ALIAS)"
[ -z "$ALIAS_USE" ] && ALIAS_USE="${KEY_ALIAS:-key0}"

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
hint "Pour build-and-publish :"
code "export KEY_STORE_PASSWORD='…'"
code "export KEY_PASSWORD=\"\$KEY_STORE_PASSWORD\""
code "export ALIAS=$ALIAS_USE"
code "./scripts/build-and-publish.sh -y --track internal"

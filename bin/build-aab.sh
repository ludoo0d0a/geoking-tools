#!/usr/bin/env bash
#
# Build a SIGNED release AAB locally with the upload keystore.
#
# Usage:
#   ./scripts/build-aab.sh                 # version from playstore/version.properties
#   ./scripts/build-aab.sh 3               # versionCode 3
#   ./scripts/build-aab.sh 3 1.0.1         # versionCode 3, versionName 1.0.1
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
# shellcheck source=../lib/gradle-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/gradle-env.sh"
gk_project_init
cd "$ROOT"

[ -f "$KS_PATH" ]   || die "release.keystore introuvable à la racine du projet."
[ -f "$CRED" ] || die "scripts/.keystore-credentials introuvable."
KEYSTORE_PASSWORD="$(grep '^KEYSTORE_PASSWORD=' "$CRED" | cut -d= -f2-)"
KEY_ALIAS="$(grep '^KEY_ALIAS=' "$CRED" | cut -d= -f2-)"
KEY_PASSWORD="$(grep '^KEY_PASSWORD=' "$CRED" | cut -d= -f2-)"
[ -n "$KEYSTORE_PASSWORD" ] && [ -n "$KEY_ALIAS" ] || die "credentials incomplets dans $CRED."

EXPECT_SHA1="$(keytool -list -v -keystore "$KS_PATH" -alias "$KEY_ALIAS" -storepass "$KEYSTORE_PASSWORD" 2>/dev/null \
               | awk -F'SHA1: ' '/SHA1:/{print $2; exit}')"
[ -n "$EXPECT_SHA1" ] || die "Impossible de lire l'empreinte du keystore."
printf 'Clé de signature : alias %s%s%s — SHA1 attendu %s%s%s\n' \
  "$c_bold" "$KEY_ALIAS" "$c_off" "$c_bold" "$EXPECT_SHA1" "$c_off"

gk_setup_build_env "$ROOT"

[ -n "${1:-}" ] && export VERSION_CODE="$1"
[ -n "${2:-}" ] && export VERSION_NAME="$2"
[ -n "${VERSION_CODE:-}" ] && echo "versionCode forcé : $VERSION_CODE"
[ -n "${VERSION_NAME:-}" ] && echo "versionName forcé : $VERSION_NAME"

echo
echo "${c_dim}→ build du bundle release signé…${c_off}"
KEYSTORE_FILE="$KS_PATH" \
KEYSTORE_PASSWORD="$KEYSTORE_PASSWORD" \
KEY_ALIAS="$KEY_ALIAS" \
KEY_PASSWORD="$KEY_PASSWORD" \
"${GRADLE[@]}" "${GRADLE_MODULE}:bundleRelease" --no-daemon --stacktrace

MODULE_PATH="${GRADLE_MODULE#:}"
AAB="$ROOT/$MODULE_PATH/build/outputs/bundle/release/${MODULE_PATH}-release.aab"
[ -f "$AAB" ] || die "AAB non produit ($AAB)."

GOT_SHA1="$(keytool -printcert -jarfile "$AAB" 2>/dev/null \
            | awk -F'SHA1: ' '/SHA1:/{print $2; exit}')"
echo
ok "AAB : $AAB"
echo "SHA1 du bundle : ${c_bold}${GOT_SHA1:-?}${c_off}"
if [ "$GOT_SHA1" = "$EXPECT_SHA1" ]; then
  ok "Signature CONFORME à la clé attendue par Play. Prêt à uploader."
else
  die "Signature DIFFÉRENTE (attendu $EXPECT_SHA1). Ne pas uploader cet AAB."
fi
echo
echo "Uploade ce fichier dans Play Console → Test interne → Créer une release."

#!/usr/bin/env bash
#
# Generate an upload signing keystore and optional GitHub Actions secrets.
#
# Usage:
#   ./scripts/gen-keystore.sh          # create keystore + save credentials locally
#   ./scripts/gen-keystore.sh --gh     # also push the 4 secrets to GitHub (needs gh)
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
geoking_project_init
cd "$ROOT"

command -v keytool >/dev/null 2>&1 || die "keytool introuvable — installe un JDK (ex. Temurin 21)."

if [ -f "$KS_PATH" ]; then
  fail "$KS_PATH existe déjà — refus d'écraser la clé de signature."
  hint "Supprime-le d'abord si tu veux vraiment en générer une nouvelle."
  exit 1
fi

PASS="$(openssl rand -base64 48 | LC_ALL=C tr -dc 'A-Za-z0-9')"
PASS="${PASS:0:28}"

say "🔐 Génération du keystore → $KS_PATH"
keytool -genkeypair -v \
  -keystore "$KS_PATH" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "$KEYSTORE_DN" >/dev/null

B64="$(base64 < "$KS_PATH" | tr -d '\n')"

umask 077
cat > "$CRED" <<EOF
# Signing credentials — NE PAS COMMITER. Généré $(date -u +%Y-%m-%dT%H:%M:%SZ)
KEYSTORE_PASSWORD=$PASS
KEY_ALIAS=$ALIAS
KEY_PASSWORD=$PASS
EOF
chmod 600 "$CRED"

ok "Keystore créé."
hint "Identifiants (gitignored) : scripts/.keystore-credentials"
blank
subhead "Empreintes certificat (Google Sign-In / Firebase)"
keytool -list -v -keystore "$KS_PATH" -alias "$ALIAS" -storepass "$PASS" 2>/dev/null \
  | grep -E 'SHA1:|SHA256:' || true
blank

if [ "${1:-}" = "--gh" ]; then
  need gh
  subhead "Secrets GitHub Actions"
  printf '%s' "$B64"   | gh secret set KEYSTORE_BASE64
  printf '%s' "$PASS"  | gh secret set KEYSTORE_PASSWORD
  printf '%s' "$ALIAS" | gh secret set KEY_ALIAS
  printf '%s' "$PASS"  | gh secret set KEY_PASSWORD
  ok "KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD"
  hint "Encore requis : PLAY_SERVICE_ACCOUNT_JSON (voir README)"
else
  hint "Pousser les secrets : ./scripts/gen-keystore.sh --gh"
  code "base64 < release.keystore | tr -d '\\n' | pbcopy"
fi

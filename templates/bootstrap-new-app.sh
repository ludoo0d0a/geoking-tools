#!/usr/bin/env bash
# Scaffold geoking-tools + geoking-ci integration into the current app repo.
#
# Usage (from app root):
#   ../geoking-tools/templates/bootstrap-new-app.sh
#   ../geoking-tools/templates/bootstrap-new-app.sh --package fr.geoking.myapp --name MyApp
#
set -euo pipefail

APP_ROOT="$(pwd)"
TOOLS="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE=""
APP_NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --package) PACKAGE="${2:?}"; shift 2 ;;
    --name) APP_NAME="${2:?}"; shift 2 ;;
    -h|--help)
      sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Option inconnue : $1" >&2; exit 2 ;;
  esac
done

[ -f "settings.gradle.kts" ] || [ -f "settings.gradle" ] || {
  echo "Lance ce script depuis la racine d'un projet Gradle (settings.gradle.kts)." >&2
  exit 1
}

mkdir -p scripts .github/workflows .github/actions/setup-gradle

# --- scripts ---
cp "$TOOLS/templates/_geoking-wrapper.sh" scripts/
chmod +x scripts/_geoking-wrapper.sh

for s in setup-release show-secrets verify-oauth gen-keystore build-aab deploy-device adb-reconnect; do
  printf '#!/usr/bin/env bash\nGEOKING_SCRIPT=%s.sh exec "$(dirname "$0")/_geoking-wrapper.sh" "$@"\n' "$s" > "scripts/$s.sh"
  chmod +x "scripts/$s.sh"
done

cp "$TOOLS/templates/whatsnew.py" scripts/
chmod +x scripts/whatsnew.py

if [ ! -f scripts/project.manifest.json ]; then
  cp "$TOOLS/templates/project.manifest.json" scripts/project.manifest.json
  if [ -n "$PACKAGE" ]; then
    command -v jq >/dev/null 2>&1 || { echo "jq requis pour --package" >&2; exit 1; }
    tmp="$(mktemp)"
    jq --arg p "$PACKAGE" --arg n "${APP_NAME:-App}" \
      '.project.package = $p | .project.name = $n | .build.keystoreDn = ("CN=" + $n + ", OU=GeoKing, O=GeoKing, L=Paris, C=FR") | .build.signInLogTag = ($n + "SignIn")' \
      scripts/project.manifest.json > "$tmp"
    mv "$tmp" scripts/project.manifest.json
  fi
  echo "✓ scripts/project.manifest.json créé — complète les URLs consoles"
else
  echo "· scripts/project.manifest.json existe déjà — conservé"
fi

# --- CI ---
if [ ! -f .github/actions/setup-gradle/action.yml ]; then
  cp "$TOOLS/templates/setup-gradle/action.yml" .github/actions/setup-gradle/action.yml
  echo "✓ .github/actions/setup-gradle"
else
  echo "· setup-gradle action existe déjà"
fi

if [ ! -f .github/workflows/android-ci.yml ]; then
  cp "$TOOLS/templates/android-ci.yml" .github/workflows/android-ci.yml
  echo "✓ .github/workflows/android-ci.yml — édite artifact_name"
else
  echo "· android-ci.yml existe déjà"
fi

if [ ! -f .github/workflows/release-play.yml ]; then
  cp "$TOOLS/templates/release-play.yml" .github/workflows/release-play.yml
  if [ -n "$PACKAGE" ]; then
    sed -i.bak "s/fr.geoking.MYAPP/$PACKAGE/g" .github/workflows/release-play.yml && rm -f .github/workflows/release-play.yml.bak
  fi
  echo "✓ .github/workflows/release-play.yml — vérifie package_name"
else
  echo "· release-play.yml existe déjà"
fi

# --- gitignore ---
if [ -f .gitignore ]; then
  if ! grep -q 'scripts/.keystore-credentials' .gitignore 2>/dev/null; then
    printf '\n%s\n' "# geoking-tools" >> .gitignore
    grep -v '^#' "$TOOLS/templates/gitignore.snippet" | grep -v '^$' >> .gitignore
    echo "✓ entrées ajoutées à .gitignore"
  else
    echo "· .gitignore déjà à jour"
  fi
else
  cp "$TOOLS/templates/gitignore.snippet" .gitignore
  echo "✓ .gitignore créé"
fi

# --- playstore minimum ---
mkdir -p playstore
if [ ! -f playstore/version.properties ]; then
  printf 'versionCode=1\nversionName=1.0.0\n' > playstore/version.properties
  echo "✓ playstore/version.properties"
fi
if [ ! -f playstore/whatsnew.xml ]; then
  cat > playstore/whatsnew.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<releases>
  <release versionCode="1" versionName="1.0.0">
    <locale code="fr-FR">Première version.</locale>
    <locale code="en-US">First release.</locale>
  </release>
</releases>
EOF
  echo "✓ playstore/whatsnew.xml"
fi

echo
echo "Prochaines étapes :"
echo "  1. Édite scripts/project.manifest.json (URLs Firebase, GCP, Play)"
echo "  2. Guide complet : $TOOLS/INTEGRATION.md"
echo "  3. ./scripts/setup-release.sh"
echo "  4. Sync workflows from geoking-ci when upgrading (templates/ in geoking-tools)"

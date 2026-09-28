#!/usr/bin/env bash
# App-string i18n (DeepL) — runs the app-local i18n/ tree (gk-i18n layout).
#
# Bootstrap once from the app root:
#   mkdir -p i18n && cp -R "$GK_TOOLS/translate/"* i18n/
#   # edit i18n/translate.sh (--modules), i18n/languages.py, add i18n/.env
#
# Usage:
#   ./scripts/translate-strings.sh
#   ./scripts/translate-strings.sh --help   # if your i18n/translate.sh supports it
#
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
gk_project_init

I18N="$ROOT/i18n"
if [ ! -f "$I18N/translate.sh" ] && [ ! -f "$I18N/translate.py" ]; then
  echo "i18n/ introuvable dans $ROOT" >&2
  echo "Bootstrap :" >&2
  echo "  mkdir -p i18n && cp -R \"\$GK_TOOLS/translate/\"* i18n/" >&2
  echo "  # puis édite i18n/translate.sh (--modules) et i18n/.env (DEEPL_API_KEY)" >&2
  echo "Voir skill gk-i18n / geoking-tools/translate/README.md" >&2
  exit 1
fi

cd "$I18N"
if [ -f ./translate.sh ]; then
  exec bash ./translate.sh "$@"
fi
exec python3 ./translate.py "$@"

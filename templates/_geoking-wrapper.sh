#!/usr/bin/env bash
# Delegates to geoking-tools (sibling repo or GEOKING_TOOLS).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GEOKING_PROJECT_ROOT="$ROOT"
if [ -n "${GEOKING_TOOLS:-}" ] && [ -d "$GEOKING_TOOLS" ]; then
  TOOLS="$GEOKING_TOOLS"
else
  for _c in "$ROOT/../geoking-tools" "$HOME/dev/android/geoking-tools"; do
    if [ -d "$_c" ]; then TOOLS="$(cd "$_c" && pwd)"; break; fi
  done
fi
[ -n "${TOOLS:-}" ] || { echo "geoking-tools introuvable — clone ../geoking-tools ou exporte GEOKING_TOOLS" >&2; exit 1; }
SCRIPT="${GEOKING_SCRIPT:-$(basename "$0")}"
exec "$TOOLS/bin/$SCRIPT" "$@"

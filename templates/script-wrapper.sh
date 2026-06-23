#!/usr/bin/env bash
# Thin wrapper — delegates to geoking-tools. Copy into your app's scripts/ directory.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GEOKING_PROJECT_ROOT="$ROOT"
_LIB="$(cd "$ROOT/../geoking-tools/lib" 2>/dev/null && pwd)" || true
if [ -z "${_LIB:-}" ]; then
  for _c in "$ROOT/../geoking-tools" "$HOME/dev/android/geoking-tools"; do
    [ -d "$_c" ] && _LIB="$_c/lib" && break
  done
fi
# shellcheck source=resolve.sh
. "${_LIB:?geoking-tools introuvable — clone à côté du projet ou exporte GEOKING_TOOLS}/resolve.sh"
TOOLS="$(geoking_tools_resolve "$ROOT")"
SCRIPT="$(basename "$0")"
exec "$TOOLS/bin/$SCRIPT" "$@"

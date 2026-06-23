#!/usr/bin/env bash
# Delegates to geoking-tools (sibling repo or GK_TOOLS).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GK_PROJECT_ROOT="$ROOT"
if [ -n "${GK_TOOLS:-}" ] && [ -d "$GK_TOOLS" ]; then
  TOOLS="$GK_TOOLS"
else
  for _c in "$ROOT/../geoking-tools" "$HOME/dev/android/geoking-tools"; do
    if [ -d "$_c" ]; then TOOLS="$(cd "$_c" && pwd)"; break; fi
  done
fi
[ -n "${TOOLS:-}" ] || { echo "geoking-tools introuvable — clone ../geoking-tools ou exporte GK_TOOLS" >&2; exit 1; }
SCRIPT="${GK_SCRIPT:-$(basename "$0")}"
exec "$TOOLS/bin/$SCRIPT" "$@"

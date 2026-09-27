#!/usr/bin/env bash
# Delegates to geoking-tools (unique reference, same order as includeBuild).
#
# Resolution: $GK_TOOLS → <app>/geoking-tools → ../geoking-tools → ../../geoking-tools
#
# Entrypoints in scripts/ are symlinks to this file (see bin/link-scripts.sh).
# Basename of $0 selects geoking-tools/bin/<name>.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GK_PROJECT_ROOT="$ROOT"

TOOLS=""
if [ -n "${GK_TOOLS:-}" ] && [ -d "$GK_TOOLS" ]; then
  TOOLS="$(cd "$GK_TOOLS" && pwd)"
else
  for _c in \
    "$ROOT/geoking-tools" \
    "$ROOT/../geoking-tools" \
    "$ROOT/../../geoking-tools" \
    "$HOME/dev/android/geoking-tools"; do
    if [ -d "$_c/bin" ] || [ -d "$_c/android" ]; then
      TOOLS="$(cd "$_c" && pwd)"
      break
    fi
  done
fi
[ -n "${TOOLS:-}" ] || {
  echo "geoking-tools introuvable — ./scripts/link-scripts.sh ou clone sibling / export GK_TOOLS" >&2
  exit 1
}
export GK_TOOLS="$TOOLS"

SCRIPT="${GK_SCRIPT:-$(basename "$0")}"
case "$SCRIPT" in
  _geoking-wrapper.sh)
    echo "Invoke via ./scripts/<command> or ./scripts/gk <command> (voir link-scripts.sh)" >&2
    exit 2
    ;;
  gk)
    exec "$TOOLS/bin/gk" "$@"
    ;;
esac

if [ -f "$TOOLS/bin/$SCRIPT" ]; then
  exec "$TOOLS/bin/$SCRIPT" "$@"
fi
if [ -f "$TOOLS/bin/${SCRIPT}.sh" ]; then
  exec "$TOOLS/bin/${SCRIPT}.sh" "$@"
fi
echo "Script introuvable dans geoking-tools/bin : $SCRIPT" >&2
exit 1

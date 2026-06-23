#!/usr/bin/env bash
# Resolve geoking-tools install directory.
# Set GEOKING_TOOLS explicitly, or place geoking-tools next to the app repo.
set -euo pipefail

geoking_tools_resolve() {
  local project_root="${1:-}"

  if [ -n "${GEOKING_TOOLS:-}" ] && [ -d "$GEOKING_TOOLS" ]; then
    printf '%s' "$(cd "$GEOKING_TOOLS" && pwd)"
    return 0
  fi

  if [ -n "$project_root" ]; then
    local candidate
    for candidate in \
      "$project_root/../geoking-tools" \
      "$project_root/../../geoking-tools" \
      "$HOME/dev/android/geoking-tools"; do
      if [ -d "$candidate" ]; then
        GEOKING_TOOLS="$(cd "$candidate" && pwd)"
        printf '%s' "$GEOKING_TOOLS"
        return 0
      fi
    done
  fi

  echo "geoking-tools introuvable. Clone-le à côté du projet ou exporte GEOKING_TOOLS." >&2
  return 1
}

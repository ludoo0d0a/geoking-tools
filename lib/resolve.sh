#!/usr/bin/env bash
# Resolve geoking-tools install directory.
# Set GK_TOOLS explicitly, or place geoking-tools next to the app repo.
set -euo pipefail

gk_tools_resolve() {
  local project_root="${1:-}"

  if [ -n "${GK_TOOLS:-}" ] && [ -d "$GK_TOOLS" ]; then
    printf '%s' "$(cd "$GK_TOOLS" && pwd)"
    return 0
  fi

  if [ -n "$project_root" ]; then
    local candidate
    for candidate in \
      "$project_root/../geoking-tools" \
      "$project_root/../../geoking-tools" \
      "$HOME/dev/android/geoking-tools"; do
      if [ -d "$candidate" ]; then
        GK_TOOLS="$(cd "$candidate" && pwd)"
        printf '%s' "$GK_TOOLS"
        return 0
      fi
    done
  fi

  echo "geoking-tools introuvable. Clone-le à côté du projet ou exporte GK_TOOLS." >&2
  return 1
}

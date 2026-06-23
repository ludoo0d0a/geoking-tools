#!/usr/bin/env bash
# Bootstrap a GeoKing app project. Requires GK_PROJECT_ROOT (set by app wrappers).
set -euo pipefail

[[ -n "${GK_PROJECT_ENV_LOADED:-}" ]] && return 0
GK_PROJECT_ENV_LOADED=1

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve.sh
. "$_LIB_DIR/resolve.sh"
# shellcheck source=manifest.sh
. "$_LIB_DIR/manifest.sh"
# shellcheck source=release-lib.sh
. "$_LIB_DIR/release-lib.sh"

gk_project_init() {
  ROOT="${GK_PROJECT_ROOT:?GK_PROJECT_ROOT requis — lance via scripts/ du projet}"
  SCRIPTS="$ROOT/scripts"

  GK_TOOLS="$(gk_tools_resolve "$ROOT")"
  export GK_TOOLS ROOT SCRIPTS

  if [ -z "${GK_MANIFEST_LOADED:-}" ]; then
    GK_MANIFEST_LOADED=1
    eval "$(gk_manifest_load "$SCRIPTS/project.manifest.json")"
  fi

  gk_lib_init "$ROOT"
}

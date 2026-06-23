#!/usr/bin/env bash
# Bootstrap a GeoKing app project. Requires GEOKING_PROJECT_ROOT (set by app wrappers).
set -euo pipefail

[[ -n "${GEOKING_PROJECT_ENV_LOADED:-}" ]] && return 0
GEOKING_PROJECT_ENV_LOADED=1

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve.sh
. "$_LIB_DIR/resolve.sh"
# shellcheck source=manifest.sh
. "$_LIB_DIR/manifest.sh"
# shellcheck source=release-lib.sh
. "$_LIB_DIR/release-lib.sh"

geoking_project_init() {
  ROOT="${GEOKING_PROJECT_ROOT:?GEOKING_PROJECT_ROOT requis — lance via scripts/ du projet}"
  SCRIPTS="$ROOT/scripts"

  GEOKING_TOOLS="$(geoking_tools_resolve "$ROOT")"
  export GEOKING_TOOLS ROOT SCRIPTS

  if [ -z "${GEOKING_MANIFEST_LOADED:-}" ]; then
    GEOKING_MANIFEST_LOADED=1
    eval "$(geoking_manifest_load "$SCRIPTS/project.manifest.json")"
  fi

  geoking_lib_init "$ROOT"
}

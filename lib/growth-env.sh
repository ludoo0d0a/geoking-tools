#!/usr/bin/env bash
# Shared growth-metrics env bootstrap for GeoKing apps (Play SA, manifest, growth script dir).
set -euo pipefail

[[ -n "${GK_GROWTH_LIB_LOADED:-}" ]] && return 0
GK_GROWTH_LIB_LOADED=1

_gk_growth_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=project-env.sh
. "${_gk_growth_lib_dir}/project-env.sh"

gk_growth_env_init() {
  gk_project_init

  local manifest="${SCRIPTS}/project.manifest.json"
  export FIREBASE_PROJECT="${FIREBASE_PROJECT:-${PROJECT_ID}}"
  export GCP_PROJECT_ID="${GCP_PROJECT_ID:-$(jq -r '.project.gcpProjectId // .project.id' "$manifest")}"
  export PACKAGE="${PACKAGE:-${APP_PACKAGE}}"

  local scripts_dir
  scripts_dir="$(jq -r '.growth.scriptsDir // "scripts/growth"' "$manifest")"
  export GK_GROWTH_DIR="${GK_GROWTH_DIR:-${ROOT}/${scripts_dir}}"

  if [ -z "${GA4_PROPERTY_ID:-}" ]; then
    GA4_PROPERTY_ID="$(jq -r '.growth.ga4PropertyId // empty' "$manifest")"
    [ -n "$GA4_PROPERTY_ID" ] && [ "$GA4_PROPERTY_ID" != null ] && export GA4_PROPERTY_ID
  fi

  if [ -z "${CREDENTIALS_PATH:-}" ]; then
    local sa_file
    if sa_file="$(gk_play_sa_json_path 2>/dev/null)"; then
      export CREDENTIALS_PATH="$sa_file"
      export PLAY_SERVICE_ACCOUNT_JSON="$sa_file"
    fi
  fi
}

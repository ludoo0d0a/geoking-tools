#!/usr/bin/env bash
# GeoKing — télécharge le google-services.json officiel depuis Firebase (CLI)
# et synchronise WEB_CLIENT_ID dans local.properties.
# Alias : ./scripts/setup-release.sh config
#
# Usage :
#   ./scripts/pull-google-services.sh [--push|-p]
#     --push, -p   pousse aussi les secrets GitHub (GOOGLE_SERVICES_JSON + WEB_CLIENT_ID)
#
# Équivalent env : GK_PULL_PUSH_SECRET=true ./scripts/pull-google-services.sh
set -euo pipefail

PUSH="${GK_PULL_PUSH_SECRET:-false}"
while [ $# -gt 0 ]; do
  case "$1" in
    --push|-p) PUSH=true; shift ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; exit 2 ;;
  esac
done
export GK_PULL_PUSH_SECRET="$PUSH"

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
gk_project_init
cd "$ROOT"

gk_pull_google_services

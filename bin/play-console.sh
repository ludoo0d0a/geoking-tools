#!/usr/bin/env bash
# Play Console first-publish helpers (validate / checklist / apply-*).
#
# Usage (from app root via wrapper):
#   ./scripts/play-console.sh validate
#   ./scripts/play-console.sh checklist
#   ./scripts/play-console.sh apply-details --dry-run
#
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
gk_project_init
cd "$ROOT"

exec python3 "$GK_TOOLS/playstore-listing/play_console.py" "$@"

#!/usr/bin/env bash
# Play Store listing CLI (generate / translate / validate / upload).
#
# Usage (from app root via wrapper):
#   ./scripts/listing-cli.sh --help
#   ./scripts/listing-cli.sh generate
#   ./scripts/listing-cli.sh validate
#
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
gk_project_init
cd "$ROOT"

exec python3 "$GK_TOOLS/playstore-listing/listing_cli.py" "$@"

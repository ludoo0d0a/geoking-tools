#!/usr/bin/env bash
# GeoKing — vérifie la config Google Sign-In / Firebase Auth.
# Alias : ./scripts/setup-release.sh verify
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
gk_project_init
cd "$ROOT"

gk_verify_oauth

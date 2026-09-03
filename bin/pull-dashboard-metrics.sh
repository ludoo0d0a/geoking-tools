#!/usr/bin/env bash
# Pull app growth metrics → dashboard/data/latest.json (requires scripts/growth/pull_metrics.sh in the app).
set -euo pipefail

_gk_bin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/growth-env.sh
. "${_gk_bin_dir}/../lib/growth-env.sh"

gk_growth_env_init

_pull="${GK_GROWTH_DIR}/pull_metrics.sh"
[ -x "$_pull" ] || [ -f "$_pull" ] || {
  echo "pull-dashboard-metrics: missing ${GK_GROWTH_DIR}/pull_metrics.sh" >&2
  exit 1
}

exec "$_pull" "$@"

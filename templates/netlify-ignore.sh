#!/usr/bin/env bash
# Skip Netlify deploy when watched paths are unchanged since last successful deploy.
#
# Netlify: set in netlify.toml → ignore = "bash scripts/netlify-ignore.sh"
# Env (Netlify): CACHED_COMMIT_REF, COMMIT_REF
# Env (optional): NETLIFY_WATCH_PATHS — space-separated paths (default: website/ netlify.toml)
set -euo pipefail

if [ -z "${CACHED_COMMIT_REF:-}" ]; then
  # First deploy on this site — always build.
  exit 1
fi

paths="${NETLIFY_WATCH_PATHS:-website/ netlify.toml}"
# shellcheck disable=SC2086
git diff --quiet "$CACHED_COMMIT_REF" "$COMMIT_REF" -- $paths

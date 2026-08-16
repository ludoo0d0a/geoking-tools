#!/usr/bin/env bash
# Translate Play Store listing copy via shared i18n/translate.py (DeepL).
# Equivalent to: listing_cli.py translate  (loads i18n/.env itself).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PYTHON="${ROOT}/scripts/playstore/.venv/bin/python"
if [[ ! -x "${PYTHON}" ]]; then
  PYTHON=python3
fi
exec "${PYTHON}" "${ROOT}/scripts/playstore/listing_cli.py" translate "$@"

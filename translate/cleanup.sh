#!/bin/bash
# Run remove_unused_strings.py on all modules (app, shared, wear).
# Pass --dry-run to only report; without it, unused strings are removed.
#
# Examples:
#   ./cleanup.sh --dry-run
#   ./cleanup.sh
#   ./cleanup.sh --modules shared wear

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/remove_unused_strings.py" --modules app shared wear "$@"

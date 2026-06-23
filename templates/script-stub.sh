#!/usr/bin/env bash
# Copy to scripts/<name>.sh and set GK_SCRIPT, or rename after copy.
# Example after copy: setup-release.sh contains GK_SCRIPT=setup-release.sh
GK_SCRIPT=CHANGEME.sh exec "$(dirname "$0")/_geoking-wrapper.sh" "$@"

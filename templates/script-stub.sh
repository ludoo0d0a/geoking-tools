#!/usr/bin/env bash
# Copy to scripts/<name>.sh and set GEOKING_SCRIPT, or rename after copy.
# Example after copy: setup-release.sh contains GEOKING_SCRIPT=setup-release.sh
GEOKING_SCRIPT=CHANGEME.sh exec "$(dirname "$0")/_geoking-wrapper.sh" "$@"

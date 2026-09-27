#!/usr/bin/env bash
# Deprecated alias — use build-and-publish.sh
exec "$(cd "$(dirname "$0")" && pwd)/build-and-publish.sh" "$@"

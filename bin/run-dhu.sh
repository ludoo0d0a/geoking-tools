#!/usr/bin/env bash
#
# Run the Android Auto Desktop Head Unit (DHU) per official docs:
# https://developer.android.com/training/cars/testing/dhu
#
# DHU always talks to a physical phone (USB or ADB tunneling) — it does not
# connect to the Android emulator. App-agnostic: works for any GeoKing app.
#
# Usage:
#   ./scripts/run-dhu.sh                    # USB accessory mode (default)
#   ./scripts/run-dhu.sh --adb              # ADB tunneling (use when USB mode is flaky)
#   ./scripts/run-dhu.sh -c config/default_1080p.ini
set -euo pipefail

SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
DHU_DIR="${SDK_ROOT}/extras/google/auto"
DHU_BIN="${DHU_DIR}/desktop-head-unit"

CONFIG="config/default_720p.ini"
USE_ADB=false

while [ $# -gt 0 ]; do
  case "$1" in
    --adb) USE_ADB=true; shift ;;
    -c)    CONFIG="${2:?Missing value for -c}"; shift 2 ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 2
      ;;
    *) CONFIG="$1"; shift ;;
  esac
done

if [ ! -x "$DHU_BIN" ]; then
  echo "DHU not found at: $DHU_BIN" >&2
  echo "Install: Android Studio → SDK Manager → SDK Tools → Android Auto Desktop Head Unit Emulator" >&2
  exit 1
fi

cd "$DHU_DIR"

if [ "$USE_ADB" = true ]; then
  echo "Starting DHU with ADB Tunneling."
  echo
  echo "On the phone first:"
  echo "  1. Android Auto → overflow (⋮) → Start head unit server"
  echo "  2. Previously connected cars → Add new cars to Android Auto = on"
  echo "  3. USB connected, screen unlocked"
  echo
  if command -v adb >/dev/null 2>&1; then
    if adb forward tcp:5277 tcp:5277 2>/dev/null; then
      echo "adb forward tcp:5277 tcp:5277 done."
    else
      echo "Warning: adb forward failed. Try: adb kill-server && adb start-server && adb forward tcp:5277 tcp:5277"
    fi
  else
    echo "Warning: adb not in PATH. Run: adb forward tcp:5277 tcp:5277"
  fi
  echo "Starting DHU with config: $CONFIG"
  exec "$DHU_BIN" -c "$CONFIG"
fi

echo "Starting DHU in USB Accessory Mode (default)."
echo "Phone: connect via USB, screen unlocked."
echo "(If you see error -251 or 'Stream is broken', use: $0 --adb)"
exec "$DHU_BIN" --usb -c "$CONFIG"

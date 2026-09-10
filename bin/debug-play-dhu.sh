#!/usr/bin/env bash
#
# Build/install the debug APK on a USB-connected phone, start the Android Auto
# Desktop Head Unit (DHU), and optionally capture logcat to catch startup crashes.
#
# Usage:
#   ./scripts/debug-play-dhu.sh              # USB mode: checks, build, install, run DHU
#   ./scripts/debug-play-dhu.sh --adb        # ADB tunneling instead of USB accessory
#   ./scripts/debug-play-dhu.sh --no-build   # Skip build/install (use existing debug build)
#   ./scripts/debug-play-dhu.sh --no-dhu     # Only run checks + build/install, no DHU
#   ./scripts/debug-play-dhu.sh --logcat     # Tee `adb logcat` to build/dhu-logs/ while DHU runs
#   ./scripts/debug-play-dhu.sh -y           # Auto-confirm uninstall/reinstall on signature/downgrade clash
#
# Prerequisites (checked below):
#   - ANDROID_HOME / ANDROID_SDK_ROOT set (or default ~/Library/Android/sdk)
#   - adb in PATH, exactly one USB device connected
#   - Android Auto Desktop Head Unit installed via SDK Manager
#   - On phone: USB debugging on, Android Auto developer mode + Unknown sources enabled
#   - Default (USB) mode + --logcat: phone and this machine on the same Wi-Fi
#     (logcat rides wireless adb since USB accessory mode owns the cable).
#     --adb tunneling mode depends on the phone's "Start head unit server" dev
#     toggle, which is unreliable on some OEM ROMs — prefer default USB mode.
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
# shellcheck source=../lib/gradle-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/gradle-env.sh"
gk_project_init
cd "$ROOT"

DO_BUILD=true
DO_DHU=true
USE_ADB=false
DO_LOGCAT=false
AUTO_YES=false

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --adb)      USE_ADB=true; shift ;;
    --no-build) DO_BUILD=false; shift ;;
    --no-dhu)   DO_DHU=false; shift ;;
    --logcat)   DO_LOGCAT=true; shift ;;
    -y|--yes)   AUTO_YES=true; shift ;;
    -h|--help)  usage ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

head_ "1. Environment & tools"

SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
[ -d "$SDK_ROOT" ] || die "Android SDK not found. Set ANDROID_HOME or ANDROID_SDK_ROOT."
ok "SDK root: $SDK_ROOT"

ADB="$(command -v adb 2>/dev/null || true)"
[ -n "$ADB" ] || die "adb not found in PATH."
ok "adb: $ADB"

DHU_DIR="${SDK_ROOT}/extras/google/auto"
DHU_BIN="${DHU_DIR}/desktop-head-unit"
if [ "$DO_DHU" = true ]; then
  [ -x "$DHU_BIN" ] || die "DHU not found: $DHU_BIN — install via SDK Manager → SDK Tools → Android Auto Desktop Head Unit Emulator."
  ok "DHU: $DHU_BIN"
fi

head_ "2. USB device"

DEVICE_LINE="$("$ADB" devices | grep -E '^[[:graph:]]+[[:space:]]+device$' | grep -v ':' || true)"
DEVICE_COUNT="$(printf '%s\n' "$DEVICE_LINE" | grep -c . || true)"
[ "$DEVICE_COUNT" -gt 0 ] || die "No device connected via USB. Enable USB debugging and accept the prompt on the phone."
if [ "$DEVICE_COUNT" -gt 1 ]; then
  "$ADB" devices -l
  die "More than one USB device connected. Unplug others or use: adb -s <serial> ..."
fi
DEVICE_SERIAL="$(printf '%s\n' "$DEVICE_LINE" | awk '{print $1}')"
ok "Device: $DEVICE_SERIAL"

head_ "3. Android Auto on phone (please confirm)"

step "$PROJECT_NAME is installed on the phone (Android Auto only discovers apps already on device)."
step "Developer mode: Android Auto → About → tap version ~10x → Developer settings ON."
step "Developer settings → 'Unknown sources' / 'Add new cars' = ON."
step "Phone connected via USB, screen unlocked."
[ "$USE_ADB" = true ] && step "Developer settings → 'Start head unit server' = ON (for ADB tunneling)."

install_apk() {
  local out
  if out="$("$ADB" -s "$DEVICE_SERIAL" install -r -d "$APK" 2>&1)"; then
    printf '%s\n' "$out"
    return 0
  fi
  printf '%s\n' "$out" >&2
  if printf '%s' "$out" | grep -q "INSTALL_FAILED_UPDATE_INCOMPATIBLE\|INSTALL_FAILED_VERSION_DOWNGRADE"; then
    warn "Device has an incompatible build installed (different signature or higher versionCode)."
    if [ "$AUTO_YES" = true ] || confirm "Uninstall ${APP_PACKAGE} from the device and retry? (wipes local app data)"; then
      "$ADB" -s "$DEVICE_SERIAL" uninstall "$APP_PACKAGE" || true
      "$ADB" -s "$DEVICE_SERIAL" install -r -d "$APK"
      return $?
    fi
  fi
  return 1
}

if [ "$DO_BUILD" = true ]; then
  head_ "4. Build & install (debug)"
  gk_setup_build_env "$ROOT"
  MODULE_PATH="${GRADLE_MODULE#:}"
  APK="$ROOT/$MODULE_PATH/build/outputs/apk/debug/${MODULE_PATH}-debug.apk"
  "${GRADLE[@]}" "${GRADLE_MODULE}:assembleDebug" --no-daemon
  [ -f "$APK" ] || die "APK not found: $APK"
  install_apk || die "Install failed on $DEVICE_SERIAL."
  ok "Installed debug build on $DEVICE_SERIAL"
else
  head_ "4. Build & install (skipped with --no-build)"
  warn "Make sure a debug build is already installed on the device."
fi

LOG_FILE=""
if [ "$DO_LOGCAT" = true ]; then
  LOGCAT_TARGET="$DEVICE_SERIAL"
  if [ "$USE_ADB" = false ]; then
    # USB accessory mode hands the cable to DHU's AOA protocol, which kills any
    # adb session riding the same USB link. Capture logcat over wireless adb
    # instead so it survives the whole DHU session.
    PHONE_IP="$("$ADB" -s "$DEVICE_SERIAL" shell "ip route get 1.1.1.1 2>/dev/null" 2>/dev/null \
      | sed -n 's/.* src \([0-9.]*\).*/\1/p' | tr -d '\r')"
    if [ -z "$PHONE_IP" ]; then
      warn "Could not detect the phone's Wi-Fi IP — logcat will ride the USB link and likely cut out once DHU connects."
    else
      "$ADB" -s "$DEVICE_SERIAL" tcpip 5555 >/dev/null 2>&1 || true
      sleep 1
      if "$ADB" connect "${PHONE_IP}:5555" 2>&1 | grep -q "connected\|already"; then
        LOGCAT_TARGET="${PHONE_IP}:5555"
        ok "Wireless adb for logcat: $LOGCAT_TARGET (phone + this Mac must share Wi-Fi)"
      else
        warn "Wireless adb connect failed — logcat will ride the USB link and likely cut out once DHU connects."
      fi
    fi
  fi
  LOG_DIR="$ROOT/build/dhu-logs"
  mkdir -p "$LOG_DIR"
  LOG_FILE="$LOG_DIR/dhu-$(date +%Y%m%d-%H%M%S).log"
  "$ADB" -s "$LOGCAT_TARGET" logcat -c
  "$ADB" -s "$LOGCAT_TARGET" logcat -v threadtime > "$LOG_FILE" 2>&1 &
  LOGCAT_PID=$!
  trap 'kill "$LOGCAT_PID" 2>/dev/null || true' EXIT
  ok "Capturing logcat to $LOG_FILE"
fi

if [ "$DO_DHU" = false ]; then
  head_ "5. DHU (skipped with --no-dhu)"
  step "Start DHU manually: ./scripts/run-dhu.sh"
  step "Open $PROJECT_NAME once on the phone so Android Auto sees it."
  step "In DHU: start an Android Auto session."
  exit 0
fi

head_ "5. Start DHU"

step "Open $PROJECT_NAME once on the phone so Android Auto sees it."
step "In DHU: start an Android Auto session; $PROJECT_NAME should appear under Media."
[ "$DO_LOGCAT" = true ] && step "Reproduce the crash, then close DHU (or Ctrl+C) — the trace will be saved in $LOG_FILE."

CONFIG="config/default_720p.ini"
cd "$DHU_DIR"
if [ "$USE_ADB" = true ]; then
  "$ADB" forward tcp:5277 tcp:5277 2>/dev/null || warn "adb forward failed. Try: adb kill-server && adb start-server"
  "$DHU_BIN" -c "$CONFIG"
else
  "$DHU_BIN" --usb -c "$CONFIG"
fi

if [ -n "$LOG_FILE" ]; then
  blank
  ok "Logcat saved: $LOG_FILE"
  step "Look for 'FATAL EXCEPTION' or '${APP_PACKAGE}' to find the crash."
fi

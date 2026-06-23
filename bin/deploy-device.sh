#!/usr/bin/env bash
#
# Build an APK, wait for a device, then install.
#
# Usage:
#   ./scripts/deploy-device.sh              # prompts: debug/release, launch y/n
#   ./scripts/deploy-device.sh -l           # skip launch prompt (yes)
#   ./scripts/deploy-device.sh -s SERIAL    # pick a device (adb devices)
#   ./scripts/deploy-device.sh -s IP:PORT   # wireless adb (auto-reconnect)
#   ./scripts/deploy-device.sh -r           # skip build-type prompt (release)
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
# shellcheck source=../lib/gradle-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/gradle-env.sh"
geoking_project_init
cd "$ROOT"

LAUNCH_ACTIVITY="${LAUNCH_ACTIVITY:?manifest build.mainActivity requis}"
LAUNCH=-1
BUILD_TYPE=""
DEVICE=""
WIRELESS_TARGET=""

cleanup() {
  type adb_wireless_stop_background >/dev/null 2>&1 && adb_wireless_stop_background || true
}

on_interrupt() {
  echo
  printf '%sInterrompu.%s\n' "$c_dim" "$c_off" >&2
  cleanup
  exit 130
}

trap cleanup EXIT
trap on_interrupt INT TERM

read_interactive() {
  local __var="$1"
  if ( : </dev/tty ) 2>/dev/null; then
    IFS= read -r "$__var" </dev/tty || return $?
  else
    IFS= read -r "$__var" || return $?
  fi
}

prompt_default() {
  local prompt="$1" default="$2" reply
  printf '%s [%s]: ' "$prompt" "$default" >&2
  read_interactive reply
  printf '%s' "${reply:-$default}"
}

tolower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    -l|--launch) LAUNCH=1; shift ;;
    -r|--release) BUILD_TYPE=release; shift ;;
    -s|--device) DEVICE="${2:-}"; [ -n "$DEVICE" ] || die "Missing value for $1"; shift 2 ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

if [ -z "$BUILD_TYPE" ] || [ "$LAUNCH" -lt 0 ]; then
  echo >&2
  echo "${c_bold}Configuration du déploiement${c_off}" >&2
fi

if [ -z "$BUILD_TYPE" ]; then
  reply="$(prompt_default "Type de build (debug/release)" "debug")"
  reply="$(tolower "$reply")"
  case "$reply" in
    debug|d) BUILD_TYPE=debug ;;
    release|r) BUILD_TYPE=release ;;
    *) die "Type invalide : $reply (debug ou release)" ;;
  esac
fi

if [ "$LAUNCH" -lt 0 ]; then
  reply="$(prompt_default "Lancer l'app après installation ? (y/n)" "n")"
  reply="$(tolower "$reply")"
  case "$reply" in
    y|yes|oui|o) LAUNCH=1 ;;
    n|no|non) LAUNCH=0 ;;
    *) die "Réponse invalide : $reply (y ou n)" ;;
  esac
fi

geoking_setup_build_env "$ROOT"

MODULE_PATH="${GRADLE_MODULE#:}"
GRADLE_TASK="${GRADLE_MODULE}:assembleDebug"
APK="$ROOT/$MODULE_PATH/build/outputs/apk/debug/${MODULE_PATH}-debug.apk"
if [ "$BUILD_TYPE" = "release" ]; then
  GRADLE_TASK="${GRADLE_MODULE}:assembleRelease"
  APK="$ROOT/$MODULE_PATH/build/outputs/apk/release/${MODULE_PATH}-release.apk"
fi

echo
echo "${c_dim}→ build ${BUILD_TYPE}…${c_off}"
"${GRADLE[@]}" "$GRADLE_TASK" --no-daemon --stacktrace
[ -f "$APK" ] || die "APK introuvable : $APK"
ok "APK : $APK"

ADB="$(command -v adb 2>/dev/null || true)"
[ -n "$ADB" ] || die "adb introuvable."

# shellcheck source=adb-wireless.sh
source "$GEOKING_TOOLS/bin/adb-wireless.sh"

WIRELESS_TARGET="$(adb_wireless_resolve_target "$DEVICE")"
if [ -n "$WIRELESS_TARGET" ]; then
  if [ -n "$DEVICE" ] && adb_wireless_looks_like_target "$DEVICE"; then
    adb_wireless_save_target "$WIRELESS_TARGET"
  fi
  adb_wireless_ensure_connected "$WIRELESS_TARGET" || true
fi

list_devices() {
  DEVICES=()
  while IFS= read -r d; do
    [ -n "$d" ] && DEVICES+=("$d")
  done < <("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}')
}

try_wireless_reconnect() {
  [ -n "$WIRELESS_TARGET" ] || return 1
  adb_wireless_is_connected "$WIRELESS_TARGET" && return 0
  adb_wireless_ensure_connected "$WIRELESS_TARGET" || return 1
  sleep 2
}

wait_for_device() {
  echo
  echo "${c_dim}→ en attente d'un appareil pour l'installation…${c_off}"
  while true; do
    try_wireless_reconnect || true
    list_devices
    if [ "${#DEVICES[@]}" -eq 0 ]; then
      if [ -n "$WIRELESS_TARGET" ]; then sleep 3; continue; fi
      warn "Aucun appareil connecté."
      echo "Branche un téléphone (USB debugging) ou lance un émulateur, puis appuie sur Entrée."
      read_interactive _
      continue
    fi
    if [ -n "$DEVICE" ]; then
      for d in "${DEVICES[@]}"; do
        [ "$d" = "$DEVICE" ] && return 0
      done
      if [ -n "$WIRELESS_TARGET" ] && [ "$DEVICE" = "$WIRELESS_TARGET" ]; then
        sleep 3; continue
      fi
      warn "Appareil $DEVICE introuvable."
      if [ -n "$WIRELESS_TARGET" ]; then sleep 3; continue; fi
      read_interactive _
      continue
    fi
    if [ -n "$WIRELESS_TARGET" ]; then
      for d in "${DEVICES[@]}"; do
        if [ "$d" = "$WIRELESS_TARGET" ]; then DEVICE="$d"; return 0; fi
      done
    fi
    if [ "${#DEVICES[@]}" -gt 1 ]; then
      die "Plusieurs appareils (${DEVICES[*]}). Passe -s SERIAL."
    fi
    DEVICE="${DEVICES[0]}"
    return 0
  done
}

wait_for_device
export ANDROID_SERIAL="$DEVICE"
ok "Appareil : $DEVICE"

if [ -n "$WIRELESS_TARGET" ]; then
  adb_wireless_start_background "$WIRELESS_TARGET"
  ok "Reconnexion sans fil active ($WIRELESS_TARGET)"
fi

echo
echo "${c_dim}→ installation ${BUILD_TYPE} sur ${DEVICE}…${c_off}"
adb_wireless_ensure_connected "$DEVICE" || true
"$ADB" -s "$DEVICE" install -r "$APK" >/dev/null
ok "APK installé sur ${DEVICE}"

if [ "$LAUNCH" -eq 1 ]; then
  echo
  echo "${c_dim}→ lancement de $PROJECT_NAME…${c_off}"
  adb_wireless_ensure_connected "$DEVICE" || true
  "$ADB" -s "$DEVICE" shell am start -n "$LAUNCH_ACTIVITY" >/dev/null
  ok "App lancée ($LAUNCH_ACTIVITY)"
fi

echo
ok "Déployé sur ${c_bold}${DEVICE}${c_off}."

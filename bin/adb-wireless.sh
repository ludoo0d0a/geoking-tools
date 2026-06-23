# Shared wireless adb helpers — source from deploy-device.sh / adb-reconnect.sh.
: "${ROOT:?ROOT must be set before sourcing adb-wireless.sh}"
: "${ADB:?ADB must be set}"

ADB_WIRELESS_CONFIG="${ADB_WIRELESS_CONFIG:-$ROOT/scripts/.adb-wireless}"
ADB_WIRELESS_INTERVAL="${ADB_WIRELESS_INTERVAL:-30}"
ADB_WIRELESS_PID=""

adb_wireless_looks_like_target() {
  case "$1" in *:*) return 0 ;; *) return 1 ;; esac
}

adb_wireless_read_config() {
  [ -f "$ADB_WIRELESS_CONFIG" ] || return 1
  tr -d '[:space:]' < "$ADB_WIRELESS_CONFIG"
}

adb_wireless_save_target() {
  printf '%s\n' "$1" > "$ADB_WIRELESS_CONFIG"
}

adb_wireless_resolve_target() {
  local hint="${1:-}" saved=""
  if [ -n "$hint" ] && adb_wireless_looks_like_target "$hint"; then
    printf '%s' "$hint"
    return 0
  fi
  if saved="$(adb_wireless_read_config)"; then
    [ -n "$saved" ] && printf '%s' "$saved"
  fi
  return 0
}

adb_wireless_is_connected() {
  local target="$1"
  "$ADB" devices 2>/dev/null | awk -v t="$target" 'NR>1 && $1==t && $2=="device" {found=1} END{exit !found}'
}

adb_wireless_try_connect() {
  local target="$1" out
  out="$("$ADB" connect "$target" 2>&1)" || true
  case "$out" in
    *connected*|*already*) return 0 ;;
    *) [ -n "$out" ] && printf '%s\n' "$out" >&2; return 1 ;;
  esac
}

adb_wireless_ensure_connected() {
  local target="$1"
  adb_wireless_is_connected "$target" && return 0
  adb_wireless_try_connect "$target" && adb_wireless_is_connected "$target"
}

adb_wireless_reconnect_loop() {
  local target="$1" interval="${2:-$ADB_WIRELESS_INTERVAL}" state="" new_state=""
  while true; do
    if adb_wireless_is_connected "$target"; then
      new_state=connected
    elif adb_wireless_try_connect "$target" && adb_wireless_is_connected "$target"; then
      new_state=connected
    else
      new_state=disconnected
    fi

    if [ "$new_state" != "$state" ]; then
      case "$new_state" in
        connected)
          printf '%s✓ %s en ligne%s\n' "${c_ok:-}" "$target" "${c_off:-}"
          ;;
        disconnected)
          printf '%s⚠ %s hors ligne — nouvelle tentative dans %ss%s\n' \
            "${c_err:-}" "$target" "$interval" "${c_off:-}" >&2
          ;;
      esac
      state="$new_state"
    fi

    sleep "$interval"
  done
}

adb_wireless_start_background() {
  local target="$1" interval="${2:-$ADB_WIRELESS_INTERVAL}"
  [ -n "$ADB_WIRELESS_PID" ] && kill "$ADB_WIRELESS_PID" 2>/dev/null || true
  adb_wireless_reconnect_loop "$target" "$interval" &
  ADB_WIRELESS_PID=$!
}

adb_wireless_stop_background() {
  [ -n "$ADB_WIRELESS_PID" ] || return 0
  kill "$ADB_WIRELESS_PID" 2>/dev/null || true
  wait "$ADB_WIRELESS_PID" 2>/dev/null || true
  ADB_WIRELESS_PID=""
}

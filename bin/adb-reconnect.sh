#!/usr/bin/env bash
#
# Keep wireless adb alive by reconnecting in a loop.
#
# Usage:
#   ./scripts/adb-reconnect.sh 192.168.1.42:5555
#   ./scripts/adb-reconnect.sh -s 192.168.1.42:5555
#   ./scripts/adb-reconnect.sh
#   ./scripts/adb-reconnect.sh -i 15 192.168.1.42:5555
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
gk_project_init
cd "$ROOT"

INTERVAL=30
SAVE=0
TARGET=""

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    -i|--interval) INTERVAL="${2:-}"; [ -n "$INTERVAL" ] || die "Missing value for $1"; shift 2 ;;
    -s|--save) SAVE=1; shift ;;
    -h|--help) usage ;;
    -*) die "Unknown option: $1 (try --help)" ;;
    *) TARGET="$1"; shift ;;
  esac
done

case "$INTERVAL" in
  ''|*[!0-9]*) die "Interval invalide : $INTERVAL" ;;
esac
[ "$INTERVAL" -gt 0 ] || die "Interval invalide : $INTERVAL"

ADB="$(command -v adb 2>/dev/null || true)"
[ -n "$ADB" ] || die "adb introuvable."

# shellcheck source=adb-wireless.sh
source "$GK_TOOLS/bin/adb-wireless.sh"

TARGET="$(adb_wireless_resolve_target "$TARGET")"
[ -n "$TARGET" ] || die "Cible manquante. Passe IP:PORT ou -s pour enregistrer."

if [ "$SAVE" -eq 1 ]; then
  adb_wireless_save_target "$TARGET"
  ok "Cible enregistrée dans scripts/.adb-wireless"
fi

trap 'printf "\n%sArrêt.%s\n" "$c_dim" "$c_off"; exit 0' INT TERM

ok "Reconnexion adb vers ${c_bold}${TARGET}${c_off} toutes les ${INTERVAL}s (Ctrl+C pour arrêter)"
printf '%sAstuce : garde le Wi-Fi actif en veille + « Rester activé » (options développeur).%s\n\n' "$c_dim" "$c_off"

adb_wireless_reconnect_loop "$TARGET" "$INTERVAL"

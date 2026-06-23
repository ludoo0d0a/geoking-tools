#!/usr/bin/env bash
# Terminal UI helpers for GeoKing scripts.
set -euo pipefail

[[ -n "${GK_UI_LOADED:-}" ]] && return 0
GK_UI_LOADED=1

c_reset=$'\033[0m'
c_bold=$'\033[1m'
c_dim=$'\033[2m'
c_ok=$'\033[32m'
c_warn=$'\033[33m'
c_err=$'\033[31m'
c_cyan=$'\033[36m'
c_link=$'\033[4;94m'
c_off=$'\033[0m'

if [ -n "${NO_COLOR:-}" ]; then
  c_bold= c_dim= c_ok= c_warn= c_err= c_cyan= c_link= c_off= c_reset=
fi

blank()  { printf '\n'; }
rule()   { printf '%s  ─────────────────────────────────────────────────────%s\n' "$c_dim" "$c_off"; }
say()    { printf '%s\n' "$*"; }

head_() {
  blank
  rule
  printf '  %s◆ %s%s\n' "$c_bold" "$*" "$c_off"
  rule
}

subhead() { blank; printf '  %s▸ %s%s\n' "$c_cyan" "$*" "$c_off"; }

ok()   { printf '  %s✓%s  %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '  %s⚠%s   %s\n' "$c_warn" "$c_off" "$*"; }
fail() { printf '  %s✗%s  %s\n' "$c_err" "$c_off" "$*"; }
die()  { fail "$*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Outil requis introuvable : $1"; }

hint() { printf '     %s│%s %s\n' "$c_dim" "$c_off" "$*"; }
code() { printf '     %s$%s %s\n' "$c_dim" "$c_off" "$*"; }
step() { printf '  %s●%s %s\n' "$c_cyan" "$c_off" "$*"; }

show_url() { printf '     🔗 %s%s%s\n' "$c_link" "$1" "$c_off"; }

show_link() {
  local label="$1" url="$2"
  printf '     %-16s 🔗 %s%s%s\n' "$label" "$c_link" "$url" "$c_off"
}

info_box() {
  printf '  %s┌─%s\n' "$c_dim" "$c_off"
  while [ $# -gt 0 ]; do
    printf '  %s│%s %s\n' "$c_dim" "$c_off" "$1"
    shift
  done
  printf '  %s└─%s\n' "$c_dim" "$c_off"
}

sedi(){ if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }

ask()    { local p="$1" a; printf '  %s?%s %s' "$c_cyan" "$c_off" "$p"; read -r -p " " a; printf '%s' "$a"; }
confirm(){ local a; printf '  %s?%s %s' "$c_cyan" "$c_off" "$1 [o/N] "; read -r -p "" a
           [ "$a" = o ] || [ "$a" = O ] || [ "$a" = y ] || [ "$a" = Y ]; }

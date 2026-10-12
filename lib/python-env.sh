#!/usr/bin/env bash
# Resolve a runnable python3 — skip Intel Homebrew leftovers on Apple Silicon
# (/usr/local/bin/python3 → "Bad CPU type in executable").
set -euo pipefail

[[ -n "${GK_PYTHON_ENV_LOADED:-}" ]] && return 0
GK_PYTHON_ENV_LOADED=1

gk_python_works() {
  local bin="${1:-}"
  [ -n "$bin" ] && [ -x "$bin" ] || return 1
  "$bin" -c 'import sys' >/dev/null 2>&1
}

gk_python_resolve() {
  if [ -n "${GK_PYTHON:-}" ] && gk_python_works "$GK_PYTHON"; then
    printf '%s' "$GK_PYTHON"
    return 0
  fi
  local c p
  for c in \
    "${PYTHON:-}" \
    "${PYTHON3:-}" \
    /opt/homebrew/bin/python3 \
    /usr/bin/python3
  do
    [ -n "$c" ] || continue
    gk_python_works "$c" || continue
    printf '%s' "$c"
    return 0
  done
  while IFS= read -r p; do
    gk_python_works "$p" || continue
    printf '%s' "$p"
    return 0
  done < <(type -aP python3 2>/dev/null || true)
  return 1
}

# Export GK_PYTHON and put its directory first on PATH so plain `python3` works.
gk_python_ensure() {
  local bin dir
  bin="$(gk_python_resolve)" || {
    echo "python3 introuvable ou non exécutable (ex. /usr/local/bin/python3 x86_64 sur Apple Silicon)." >&2
    echo "Installe Python arm64 (brew) ou utilise /usr/bin/python3 ; ou export GK_PYTHON=/chemin/python3." >&2
    return 1
  }
  export GK_PYTHON="$bin"
  dir="$(cd "$(dirname "$bin")" && pwd)"
  # Always prepend — dir may already be on PATH *after* a broken
  # /usr/local/bin/python3 (Intel Homebrew on Apple Silicon).
  export PATH="$dir:$PATH"
}

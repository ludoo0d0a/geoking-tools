#!/usr/bin/env bash
# Link geoking-tools into an app: unique reference + scripts/ entrypoints.
#
# Same resolution order as includeBuild (gk-debug-bar):
#   $GK_TOOLS → <app>/geoking-tools → ../geoking-tools → ../../geoking-tools
#
# Usage (from app root):
#   ../geoking-tools/bin/link-scripts.sh
#   ./scripts/link-scripts.sh          # after first link
#   GK_TOOLS=/path/to/geoking-tools ../geoking-tools/bin/link-scripts.sh
#
# Creates / refreshes:
#   geoking-tools/          → relative symlink to the tools repo (skipped if real dir)
#   scripts/_geoking-wrapper.sh
#   scripts/<bin-script>    → symlink to _geoking-wrapper.sh (basename = command)
#   scripts/whatsnew.py     ← templates/whatsnew.py (Python stub; not bash wrapper)
#   scripts/gk              → symlink to _geoking-wrapper.sh  (./scripts/gk --list | <cmd>)
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$(cd "$HERE/.." && pwd)"

# App root: GK_PROJECT_ROOT, or cwd if it looks like an app, or parent of scripts/.
if [ -n "${GK_PROJECT_ROOT:-}" ]; then
  ROOT="$GK_PROJECT_ROOT"
elif [ -f settings.gradle.kts ] || [ -f settings.gradle ] || [ -f scripts/project.manifest.json ]; then
  ROOT="$(pwd)"
elif [ -f ../settings.gradle.kts ] || [ -f ../scripts/project.manifest.json ]; then
  ROOT="$(cd .. && pwd)"
else
  echo "Lance depuis la racine d'une app (settings.gradle.kts) ou exporte GK_PROJECT_ROOT." >&2
  exit 1
fi

ROOT="$(cd "$ROOT" && pwd)"
SCRIPTS="$ROOT/scripts"
mkdir -p "$SCRIPTS"

relpath() {
  python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$1" "$2"
}

# --- unique reference: <app>/geoking-tools (mirror includeBuild) ---
LINK_PATH="$ROOT/geoking-tools"
if [ -L "$LINK_PATH" ]; then
  ln -sfn "$(relpath "$TOOLS" "$ROOT")" "$LINK_PATH"
  echo "✓ geoking-tools → $(readlink "$LINK_PATH")"
elif [ -d "$LINK_PATH" ]; then
  echo "· geoking-tools/ est un dossier (checkout CI) — symlink non créé"
elif [ -e "$LINK_PATH" ]; then
  echo "⚠ geoking-tools existe déjà et n'est ni symlink ni dossier — ignoré" >&2
else
  ln -s "$(relpath "$TOOLS" "$ROOT")" "$LINK_PATH"
  echo "✓ geoking-tools → $(readlink "$LINK_PATH")"
fi

# --- wrapper (single real script in scripts/) ---
cp "$TOOLS/templates/_geoking-wrapper.sh" "$SCRIPTS/_geoking-wrapper.sh"
chmod +x "$SCRIPTS/_geoking-wrapper.sh"
echo "✓ scripts/_geoking-wrapper.sh"

# Internals: sourced by other scripts, not app entrypoints.
SKIP_LINK='
adb-wireless.sh
link-scripts.sh
'

is_skipped() {
  printf '%s' "$SKIP_LINK" | grep -qx "$1"
}

is_managed_entrypoint() {
  local f="$1"
  if [ -L "$f" ]; then
    local t; t="$(readlink "$f")"
    [ "$t" = "_geoking-wrapper.sh" ] || [ "$(basename "$t")" = "_geoking-wrapper.sh" ]
    return $?
  fi
  [ -f "$f" ] || return 1
  # Legacy 1–2 line stubs from bootstrap
  grep -q '_geoking-wrapper\.sh' "$f" 2>/dev/null
}

# Thin app stubs that only forward into geoking-tools — safe to replace with the
# bin symlink once the real entrypoint lives in geoking-tools/bin/.
is_tools_delegate() {
  local f="$1"
  [ -f "$f" ] || return 1
  [ -L "$f" ] && return 1
  grep -qE 'geoking-tools|playstore-listing|_geoking-wrapper|versionCatalogUpdate|GK_TOOLS' "$f" 2>/dev/null
}

# Python entrypoints that must stay runnable as `python3 scripts/<name>`
# (bash wrapper symlink breaks that). Prefer templates/<name> when present.
install_py_entry() {
  local name="$1"
  local dest="$SCRIPTS/$name"
  local template="$TOOLS/templates/$name"
  [ -f "$template" ] || return 1
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if is_managed_entrypoint "$dest" || is_tools_delegate "$dest" || [ "${GK_FORCE_LINK:-}" = "1" ]; then
      rm -f "$dest"
      cp "$template" "$dest"
      chmod +x "$dest"
      echo "✓ scripts/$name ← templates/$name"
    else
      echo "· scripts/$name conservé (custom)"
    fi
  else
    cp "$template" "$dest"
    chmod +x "$dest"
    echo "✓ scripts/$name ← templates/$name"
  fi
  return 0
}

link_entry() {
  local name="$1"  # e.g. setup-release.sh or gk
  local dest="$SCRIPTS/$name"

  # .py with a dedicated Python stub template (e.g. whatsnew.py)
  case "$name" in
    *.py) install_py_entry "$name" && return ;;
  esac

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if is_managed_entrypoint "$dest" || is_tools_delegate "$dest" || [ "${GK_FORCE_LINK:-}" = "1" ]; then
      ln -sfn _geoking-wrapper.sh "$dest"
      echo "✓ scripts/$name → _geoking-wrapper.sh"
    else
      echo "· scripts/$name conservé (custom)"
    fi
  else
    ln -s _geoking-wrapper.sh "$dest"
    echo "✓ scripts/$name → _geoking-wrapper.sh"
  fi
}

# Public bin commands
while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  is_skipped "$base" && continue
  link_entry "$base"
done < <(find "$TOOLS/bin" -maxdepth 1 \( -name '*.sh' -o -name '*.py' -o -name 'gk' \) -type f -print0 | sort -z)

# Dispatcher without extension
link_entry "gk"

echo
echo "Référence unique : $LINK_PATH"
echo "Entrypoint       : $SCRIPTS/gk  (ex. ./scripts/gk --list)"
echo "Compat           : ./scripts/setup-release.sh → même wrapper"

# Ensure /geoking-tools is gitignored (CI uses a real checkout at that path).
if [ -f "$ROOT/.gitignore" ] && ! grep -qE '^/geoking-tools$' "$ROOT/.gitignore" 2>/dev/null; then
  printf '\n# Local symlink to shared tools (link-scripts.sh; CI checks out the repo here)\n/geoking-tools\n' >> "$ROOT/.gitignore"
  echo "✓ /geoking-tools ajouté à .gitignore"
fi

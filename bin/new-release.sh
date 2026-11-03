#!/usr/bin/env bash
#
# Stub a new Play release: bump versionName, empty EN/FR changelog entries,
# regenerate whatsnew (no DeepL), generate listing pack from existing screenshots.
#
# Usage (from an app via thin wrapper):
#   ./scripts/new-release.sh              # bump minor (X.Y.Z → X.(Y+1).0)
#   ./scripts/new-release.sh 14.2.0       # explicit version
#   ./scripts/new-release.sh --help
#
# Reads paths from scripts/project.manifest.json (build.versionNameProperty,
# build.playStore.changelog / whatsnewScript / listingCli). Does not translate,
# recapture screenshots, upload to Play, tag, or commit.
#
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
gk_project_init
cd "$ROOT"

MANIFEST="$SCRIPTS/project.manifest.json"
need jq

usage() {
  sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage ;;
    -*) die "Unknown option: $1 (see --help)" ;;
    *)
      [ -z "$VERSION" ] || die "Unexpected argument: $1"
      VERSION="$1"
      shift
      ;;
  esac
done

VERSION_PROP="$(jq -r '.build.versionNameProperty // empty' "$MANIFEST")"
CHANGELOG_TMPL="$(jq -r '.build.playStore.changelog // "doc/playstore/changelog-{lang}.md"' "$MANIFEST")"
WHATSNEW_SCRIPT="$(jq -r '.build.playStore.whatsnewScript // "doc/playstore/whatsnew.py"' "$MANIFEST")"
LISTING_CLI="$(jq -r '.build.playStore.listingCli // "scripts/playstore/listing_cli.py"' "$MANIFEST")"

changelog_path() {
  local lang="$1"
  echo "${CHANGELOG_TMPL//\{lang\}/$lang}"
}

is_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

bump_minor() {
  local v="$1" major minor patch
  IFS=. read -r major minor patch <<<"$v"
  echo "${major}.$((minor + 1)).0"
}

read_version_from_gradle() {
  local prop="$1" build="$ROOT/build.gradle.kts"
  [ -f "$build" ] || return 1
  [ -n "$prop" ] || return 1
  grep -E "set\(\"${prop}\"," "$build" \
    | head -1 \
    | sed -E 's/.*"([^"]+)"\s*\)/\1/' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || return 1
}

read_version_from_props() {
  local props="$ROOT/playstore/version.properties"
  [ -f "$props" ] || return 1
  grep '^versionName=' "$props" | cut -d= -f2- | sed 's/^v//' | head -1
}

read_current_version() {
  local v=""
  if [ -n "$VERSION_PROP" ]; then
    v="$(read_version_from_gradle "$VERSION_PROP" || true)"
  fi
  if [ -z "$v" ]; then
    v="$(read_version_from_props || true)"
  fi
  [ -n "$v" ] || die "Could not read versionName (build.versionNameProperty / playstore/version.properties)"
  echo "$v"
}

write_version_gradle() {
  local prop="$1" new="$2" build="$ROOT/build.gradle.kts" tmp
  [ -f "$build" ] || die "Missing $build"
  grep -qE "set\(\"${prop}\"," "$build" || die "set(\"${prop}\", …) not found in build.gradle.kts"
  tmp="$(mktemp)"
  # BSD/GNU sed: rewrite only the versionName extraprop line
  sed -E "s/(set\(\"${prop}\",[[:space:]]*\")[^\"]+(\"\))/\1${new}\2/" "$build" >"$tmp"
  mv "$tmp" "$build"
}

write_version_props() {
  local new="$1" props="$ROOT/playstore/version.properties" tmp
  [ -f "$props" ] || die "Missing $props"
  tmp="$(mktemp)"
  if grep -q '^versionName=' "$props"; then
    sed "s/^versionName=.*/versionName=${new}/" "$props" >"$tmp"
  else
    printf 'versionName=%s\n' "$new" | cat - "$props" >"$tmp"
  fi
  mv "$tmp" "$props"
}

bump_version_name() {
  local new="$1"
  if [ -n "$VERSION_PROP" ] && [ -f "$ROOT/build.gradle.kts" ] \
    && grep -qE "set\(\"${VERSION_PROP}\"," "$ROOT/build.gradle.kts"; then
    write_version_gradle "$VERSION_PROP" "$new"
    ok "build.gradle.kts ${VERSION_PROP}=${new}"
  elif [ -f "$ROOT/playstore/version.properties" ]; then
    write_version_props "$new"
    ok "playstore/version.properties versionName=${new}"
  else
    die "No place to write versionName (need versionNameProperty in build.gradle.kts or playstore/version.properties)"
  fi
}

prepend_changelog_stub() {
  local file="$1" ver="$2"
  [ -f "$file" ] || die "Missing changelog: $file"
  if grep -qE "^${ver}:" "$file"; then
    die "Changelog already has ${ver}: in $file"
  fi
  "$GK_PYTHON" - "$file" "$ver" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
ver = sys.argv[2]
text = path.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)
version_at = None
for i, line in enumerate(lines):
    if line.lstrip().startswith(f"{ver}:"):
        raise SystemExit(f"Changelog already has {ver}: in {path}")
    if version_at is None and __import__("re").match(r"^\d+\.\d+\.\d+:", line.strip()):
        version_at = i
stub = f"{ver}:\n\n- \n\n"
if version_at is None:
    body = text.rstrip() + "\n\n" + stub
else:
    intro = "".join(lines[:version_at]).rstrip() + "\n\n"
    rest = "".join(lines[version_at:])
    body = intro + stub + rest
path.write_text(body, encoding="utf-8")
PY
}

prepend_changelog_index() {
  local ver="$1"
  local dir index rel
  dir="$(dirname "$(changelog_path en)")"
  index="$dir/changelog.md"
  [ -f "$index" ] || return 0
  if grep -qE "^- ${ver}$" "$index"; then
    die "changelog.md already lists ${ver}"
  fi
  "$GK_PYTHON" - "$index" "$ver" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
ver = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
out = []
inserted = False
for line in lines:
    if not inserted and line.startswith("- ") and line[2:3].isdigit():
        out.append(f"- {ver}\n")
        inserted = True
    out.append(line)
if not inserted:
    if out and not out[-1].endswith("\n"):
        out[-1] += "\n"
    out.append(f"\n- {ver}\n")
path.write_text("".join(out), encoding="utf-8")
PY
  rel="${index#"$ROOT"/}"
  ok "Prepended ${ver} in ${rel}"
}

resolve_python() {
  if [ -x "$ROOT/scripts/playstore/.venv/bin/python" ]; then
    echo "$ROOT/scripts/playstore/.venv/bin/python"
  else
    echo "$GK_PYTHON"
  fi
}

# --- start ---
CURRENT="$(read_current_version)"
if [ -z "$VERSION" ]; then
  VERSION="$(bump_minor "$CURRENT")"
fi
is_semver "$VERSION" || die "Invalid version '$VERSION' (expected X.Y.Z)"
[ "$VERSION" != "$CURRENT" ] || die "Already at ${VERSION}"

EN_CHANGELOG="$(changelog_path en)"
FR_CHANGELOG="$(changelog_path fr)"
[ -f "$EN_CHANGELOG" ] || die "Missing English changelog: $EN_CHANGELOG"
if grep -qE "^${VERSION}:" "$EN_CHANGELOG"; then
  die "English changelog already has ${VERSION}:"
fi

head_ "New release stub  ·  ${CURRENT} → ${VERSION}"
info_box \
  "Empty EN/FR changelog stubs · no DeepL" \
  "whatsnew regenerate · listing pack from existing screenshots"

bump_version_name "$VERSION"

subhead "Changelog stubs"
prepend_changelog_stub "$EN_CHANGELOG" "$VERSION"
ok "$(basename "$EN_CHANGELOG")"
if [ -f "$FR_CHANGELOG" ]; then
  prepend_changelog_stub "$FR_CHANGELOG" "$VERSION"
  ok "$(basename "$FR_CHANGELOG")"
else
  warn "No French changelog at $FR_CHANGELOG — skipped"
fi
prepend_changelog_index "$VERSION"

subhead "whatsnew (no translate)"
[ -f "$ROOT/$WHATSNEW_SCRIPT" ] || die "Missing whatsnew script: $WHATSNEW_SCRIPT"
(
  cd "$(dirname "$ROOT/$WHATSNEW_SCRIPT")"
  "$GK_PYTHON" "$(basename "$WHATSNEW_SCRIPT")"
)
ok "Regenerated whatsnew from changelogs"

PY="$(resolve_python)"
subhead "Listing pack ${VERSION}"
[ -f "$ROOT/$LISTING_CLI" ] || die "Missing listing CLI: $LISTING_CLI"
"$PY" "$ROOT/$LISTING_CLI" generate --version "$VERSION"
"$PY" "$ROOT/$LISTING_CLI" validate --version "$VERSION"
ok "listing_cli generate + validate"

ASSET_PAGES="$ROOT/scripts/playstore/generate_asset_pages.py"
if [ -f "$ASSET_PAGES" ]; then
  "$PY" "$ASSET_PAGES" --version "$VERSION"
  ok "generate_asset_pages.py"
else
  hint "No generate_asset_pages.py — skipped"
fi

blank
ok "Release stub ready: ${c_bold}${VERSION}${c_off}"
hint "Next: fill bullets in $(basename "$EN_CHANGELOG") / $(basename "$FR_CHANGELOG")"
hint "Then: cd $(dirname "$WHATSNEW_SCRIPT") && python3 $(basename "$WHATSNEW_SCRIPT") [--translate]"
hint "Optional polish: ./scripts/polish-release.sh"
hint "Ship AABs when ready: ./scripts/build-and-publish.sh"

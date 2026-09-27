#!/usr/bin/env bash
#
# Local Play Store release when GitHub Actions is unavailable (e.g. no Actions minutes).
# Mirrors geoking-ci release-play.yml: unit tests → signed AAB → whatsnew → Play upload.
#
# Usage (from an app via thin wrapper):
#   ./scripts/release-play-local.sh
#   ./scripts/release-play-local.sh --track internal
#   ./scripts/release-play-local.sh --track alpha --skip-tests
#   ./scripts/release-play-local.sh 42 1.0.1          # force versionCode / versionName
#   ./scripts/release-play-local.sh --aab path.aab    # skip build, upload existing AAB
#   ./scripts/release-play-local.sh --dry-run         # build + whatsnew only
#   ./scripts/release-play-local.sh --skip-review     # changesNotSentForReview=true
#   ./scripts/release-play-local.sh -y                # no interactive confirm
#
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
# shellcheck source=../lib/gradle-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/gradle-env.sh"
gk_project_init
cd "$ROOT"

TRACK=internal
SKIP_TESTS=false
SKIP_REVIEW=false
DRY_RUN=false
ASSUME_YES=false
STATUS=completed
EXISTING_AAB=""
FORCE_VC=""
FORCE_VN=""
UNIT_TEST_TASKS=""

usage() {
  sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

gk_confirm() {
  if [ "$ASSUME_YES" = true ]; then return 0; fi
  confirm "$@"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage ;;
    --track) TRACK="${2:?}"; shift 2 ;;
    --skip-tests) SKIP_TESTS=true; shift ;;
    --skip-review) SKIP_REVIEW=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -y|--yes) ASSUME_YES=true; shift ;;
    --draft) STATUS=draft; shift ;;
    --aab) EXISTING_AAB="${2:?}"; shift 2 ;;
    --unit-test-tasks) UNIT_TEST_TASKS="${2:?}"; shift 2 ;;
    -*)
      die "Option inconnue : $1 (voir --help)"
      ;;
    *)
      if [ -z "$FORCE_VC" ]; then
        FORCE_VC="$1"
      elif [ -z "$FORCE_VN" ]; then
        FORCE_VN="$1"
      else
        die "Argument inattendu : $1"
      fi
      shift
      ;;
  esac
done

case "$TRACK" in
  internal|alpha|beta|production) ;;
  *) die "Piste invalide : $TRACK (internal|alpha|beta|production)" ;;
esac

head_ "Release Play local  ·  $APP_ID"
info_box \
  "Fallback quand la CI GitHub Actions est indisponible (crédits)." \
  "Même chemin que geoking-ci/release-play.yml : tests → AAB → Play."

# --- service account ---
SA_FILE="$(gk_play_sa_json_path)" \
  || die "Compte de service Play introuvable. Lance ./scripts/setup-release.sh play"
need jq openssl curl
TOKEN="$(gk_google_sa_access_token "$SA_FILE")" \
  || die "Impossible d'obtenir un access token Play API."
ok "Play API authentifiée (${c_dim}$(basename "$SA_FILE")${c_off})"

# --- version ---
if [ -n "$FORCE_VC" ]; then
  VERSION_CODE="$FORCE_VC"
else
  VERSION_CODE="$(gk_play_next_version_code "$TOKEN")"
fi
if [ -n "$FORCE_VN" ]; then
  VERSION_NAME="$FORCE_VN"
elif [ -f playstore/version.properties ]; then
  VERSION_NAME="$(grep '^versionName=' playstore/version.properties | cut -d= -f2- || true)"
fi
VERSION_NAME="${VERSION_NAME:-1.0.0}"
VERSION_NAME="${VERSION_NAME#v}"

ok "versionCode=${c_bold}${VERSION_CODE}${c_off}  versionName=${c_bold}${VERSION_NAME}${c_off}  track=${c_bold}${TRACK}${c_off}"
export VERSION_CODE VERSION_NAME

# --- unit tests (CI parity) ---
if [ "$SKIP_TESTS" = true ]; then
  warn "Unit tests ignorés (--skip-tests)"
elif [ -n "$EXISTING_AAB" ]; then
  warn "Unit tests ignorés (--aab fourni)"
else
  gk_setup_build_env "$ROOT"
  if [ -z "$UNIT_TEST_TASKS" ]; then
    UNIT_TEST_TASKS="${GRADLE_MODULE}:testDebugUnitTest"
  fi
  subhead "Unit tests"
  echo "${c_dim}→ ${UNIT_TEST_TASKS}${c_off}"
  # shellcheck disable=SC2086
  "${GRADLE[@]}" $UNIT_TEST_TASKS --no-daemon --stacktrace
  ok "Tests OK"
fi

# --- signed AAB ---
MODULE_PATH="${GRADLE_MODULE#:}"
AAB="$ROOT/$MODULE_PATH/build/outputs/bundle/release/${MODULE_PATH}-release.aab"

if [ -n "$EXISTING_AAB" ]; then
  AAB="$(cd "$(dirname "$EXISTING_AAB")" && pwd)/$(basename "$EXISTING_AAB")"
  [ -f "$AAB" ] || die "AAB introuvable : $EXISTING_AAB"
  ok "AAB fourni : $AAB"
else
  subhead "Build AAB signé"
  [ -f "$KS_PATH" ]   || die "release.keystore introuvable à la racine du projet."
  [ -f "$CRED" ] || die "scripts/.keystore-credentials introuvable."
  KEYSTORE_PASSWORD="$(grep '^KEYSTORE_PASSWORD=' "$CRED" | cut -d= -f2-)"
  KEY_ALIAS="$(grep '^KEY_ALIAS=' "$CRED" | cut -d= -f2-)"
  KEY_PASSWORD="$(grep '^KEY_PASSWORD=' "$CRED" | cut -d= -f2-)"
  [ -n "$KEYSTORE_PASSWORD" ] && [ -n "$KEY_ALIAS" ] || die "credentials incomplets dans $CRED."

  EXPECT_SHA1="$(keytool -list -v -keystore "$KS_PATH" -alias "$KEY_ALIAS" -storepass "$KEYSTORE_PASSWORD" 2>/dev/null \
                 | awk -F'SHA1: ' '/SHA1:/{print $2; exit}')"
  [ -n "$EXPECT_SHA1" ] || die "Impossible de lire l'empreinte du keystore."

  gk_setup_build_env "$ROOT"
  echo "${c_dim}→ ${GRADLE_MODULE}:bundleRelease…${c_off}"
  KEYSTORE_FILE="$KS_PATH" \
  KEYSTORE_PASSWORD="$KEYSTORE_PASSWORD" \
  KEY_ALIAS="$KEY_ALIAS" \
  KEY_PASSWORD="$KEY_PASSWORD" \
  "${GRADLE[@]}" "${GRADLE_MODULE}:bundleRelease" --no-daemon --stacktrace

  [ -f "$AAB" ] || die "AAB non produit ($AAB)."
  GOT_SHA1="$(keytool -printcert -jarfile "$AAB" 2>/dev/null \
              | awk -F'SHA1: ' '/SHA1:/{print $2; exit}')"
  if [ "$GOT_SHA1" != "$EXPECT_SHA1" ]; then
    die "Signature DIFFÉRENTE (attendu $EXPECT_SHA1, obtenu ${GOT_SHA1:-?}). Ne pas uploader."
  fi
  ok "AAB signé conforme : $AAB"
fi

# --- whatsnew ---
subhead "Release notes"
WHATSNEW_PY=""
for c in "$SCRIPTS/whatsnew.py" "$GK_TOOLS/bin/whatsnew.py"; do
  [ -f "$c" ] && { WHATSNEW_PY="$c"; break; }
done
[ -n "$WHATSNEW_PY" ] || die "whatsnew.py introuvable"
GK_PROJECT_ROOT="$ROOT" python3 "$WHATSNEW_PY" "$VERSION_CODE"
ok "playstore/whatsnew/ généré"

if [ "$DRY_RUN" = true ]; then
  blank
  warn "Dry-run : pas d'upload Play."
  hint "AAB : $AAB"
  hint "Relance sans --dry-run pour publier sur ${TRACK}."
  exit 0
fi

# --- upload ---
subhead "Upload Play · piste ${TRACK}"
if [ "$SKIP_REVIEW" = true ]; then
  hint "changesNotSentForReview=true (soumission manuelle Console)"
fi
if ! gk_confirm "Uploader versionCode ${VERSION_CODE} (${VERSION_NAME}) → ${TRACK} ?"; then
  warn "Annulé — AAB conservé : $AAB"
  exit 0
fi

COMMIT_JSON="$(gk_play_release_aab "$TOKEN" "$AAB" "$TRACK" "$SKIP_REVIEW" "$STATUS")" \
  || die "Échec upload / commit Play."
ok "Commit Play OK (edit $(printf '%s' "$COMMIT_JSON" | jq -r '.id // "?"'))"

# Optionally bump local version.properties so the next local/CI build stays coherent.
if [ -f playstore/version.properties ]; then
  if gk_confirm "Mettre à jour playstore/version.properties → ${VERSION_CODE} / ${VERSION_NAME} ?"; then
    tmp="$(mktemp)"
    if grep -q '^versionCode=' playstore/version.properties; then
      sed "s/^versionCode=.*/versionCode=${VERSION_CODE}/" playstore/version.properties > "$tmp"
    else
      { printf 'versionCode=%s\n' "$VERSION_CODE"; cat playstore/version.properties; } > "$tmp"
    fi
    if grep -q '^versionName=' "$tmp"; then
      sedi "s/^versionName=.*/versionName=${VERSION_NAME}/" "$tmp"
    else
      printf 'versionName=%s\n' "$VERSION_NAME" >> "$tmp"
    fi
    mv "$tmp" playstore/version.properties
    ok "playstore/version.properties mis à jour"
  fi
fi

blank
ok "Release locale publiée sur ${c_bold}${TRACK}${c_off}"
[ -n "${PLAY_APP_DASHBOARD:-}" ] && show_link "Play Console" "$PLAY_APP_DASHBOARD"
hint "Quand les crédits Actions reviennent : préfère à nouveau la CI (geoking-ci)."

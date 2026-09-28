#!/usr/bin/env bash
# Create / update / validate scripts/project.manifest.json for a GeoKing app.
#
# Usage (from app root via wrapper):
#   ./scripts/project-manifest.sh init --package fr.geoking.myapp --name MyApp
#   ./scripts/project-manifest.sh apply --project-id myapp-123 --play-developer-id ID --play-app-id ID
#   ./scripts/project-manifest.sh fill-urls
#   ./scripts/project-manifest.sh merge-play-console
#   ./scripts/project-manifest.sh set .project.id myapp-123
#   ./scripts/project-manifest.sh get .project.package
#   ./scripts/project-manifest.sh validate
#   ./scripts/project-manifest.sh show
#
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"

# Resolve ROOT without requiring an existing manifest (init case).
_resolve_root() {
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
  MANIFEST="$SCRIPTS/project.manifest.json"
  GK_TOOLS="$(cd "$(dirname "$0")/.." && pwd)"
  TEMPLATE="$GK_TOOLS/templates/project.manifest.template.json"
  PLAY_FRAGMENT="$GK_TOOLS/templates/play-console.fragment.json"
  mkdir -p "$SCRIPTS"
}

_need_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "jq requis (brew install jq)" >&2
    exit 1
  }
}

_need_manifest() {
  [ -f "$MANIFEST" ] || {
    echo "Manifest introuvable: $MANIFEST — lance: ./scripts/project-manifest.sh init" >&2
    exit 1
  }
}

_write_json() {
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  jq -e . "$tmp" >/dev/null
  mv "$tmp" "$MANIFEST"
}

_slug_from_package() {
  local pkg="$1"
  printf '%s' "${pkg##*.}"
}

_apply_module_defaults() {
  # stdin JSON → stdout with build paths for :composeApp or :androidApp
  local module="$1"
  local mod="${module#:}"
  jq --arg module "$module" --arg mod "$mod" '
    .build.gradleModule = $module
    | .build.googleServices = ($mod + "/google-services.json")
    | .build.unitTestTasks = ($module + ":testDebugUnitTest")
    | .build.aabGlob = ($mod + "/build/outputs/bundle/release/*.aab")
    | .build.playStore.listingsDir = (.build.playStore.listingsDir // "doc/playstore/listings")
  '
}

_fill_urls_filter() {
  # Regenerates firebase/gcp/play URLs from project.id + urls.play.{developerId,appId}
  jq '
    . as $m
    | ($m.project.id // "") as $pid
    | ($m.urls.play.developerId // "PLAY_DEVELOPER_ID") as $dev
    | ($m.urls.play.appId // "PLAY_APP_ID") as $aid
    | .urls.firebase = {
        console: ("https://console.firebase.google.com/project/" + $pid + "/"),
        settings: ("https://console.firebase.google.com/project/" + $pid + "/settings/general"),
        authProviders: ("https://console.firebase.google.com/project/" + $pid + "/authentication/providers"),
        authUsers: ("https://console.firebase.google.com/project/" + $pid + "/authentication/users")
      }
    | .urls.gcp = {
        console: ("https://console.cloud.google.com/welcome?project=" + $pid),
        credentials: ("https://console.cloud.google.com/apis/credentials?project=" + $pid),
        oauthConsent: ("https://console.cloud.google.com/apis/credentials/consent?project=" + $pid),
        playDeveloperApi: ("https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com?project=" + $pid),
        serviceAccounts: ("https://console.cloud.google.com/iam-admin/serviceaccounts?project=" + $pid)
      }
    | .urls.play.dashboard = ("https://play.google.com/console/u/0/developers/" + $dev + "/app/" + $aid + "/app-dashboard")
    | .urls.play.integrity = ("https://play.google.com/console/u/0/developers/" + $dev + "/app/" + $aid + "/keymanagement")
    | .urls.play.integrityHelp = (.urls.play.integrityHelp // "https://support.google.com/googleplay/android-developer/answer/9842756?hl=fr")
    | .urls.play.usersAndPermissions = ("https://play.google.com/console/u/0/developers/" + $dev + "/users-and-permissions")
    | .urls.play.apiAccess = ("https://play.google.com/console/u/0/developers/" + $dev + "/api-access")
    | .urls.gemini.apiKeys = (.urls.gemini.apiKeys // "https://aistudio.google.com/apikey")
    | .urls.github.actionsSecrets = (.urls.github.actionsSecrets // "https://github.com/settings/secrets/actions")
  '
}

_merge_play_console() {
  [ -f "$PLAY_FRAGMENT" ] || return 0
  if jq -e '.playConsole.appType' "$MANIFEST" >/dev/null 2>&1; then
    return 0
  fi
  jq -s '.[0] * .[1]' "$MANIFEST" "$PLAY_FRAGMENT" | _write_json
  echo "✓ playConsole fusionné depuis play-console.fragment.json"
}

cmd_init() {
  local package="" name="" project_id="" module="" force=0 website=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --package) package="${2:?}"; shift 2 ;;
      --name) name="${2:?}"; shift 2 ;;
      --project-id) project_id="${2:?}"; shift 2 ;;
      --module) module="${2:?}"; shift 2 ;;
      --website) website="${2:?}"; shift 2 ;;
      --force) force=1; shift ;;
      -h|--help)
        sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
      *) echo "Option inconnue: $1" >&2; exit 2 ;;
    esac
  done

  _need_jq
  [ -f "$TEMPLATE" ] || {
    echo "Template manquant: $TEMPLATE" >&2
    exit 1
  }

  local args=()
  [ -n "$package" ] && args+=(--package "$package")
  [ -n "$name" ] && args+=(--name "$name")
  [ -n "$project_id" ] && args+=(--project-id "$project_id")
  [ -n "$module" ] && args+=(--module "$module")
  [ -n "$website" ] && args+=(--website "$website")

  if [ -f "$MANIFEST" ] && [ "$force" -ne 1 ]; then
    echo "· $MANIFEST existe déjà — conservé (passe --force pour écraser)"
    _merge_play_console
    if [ ${#args[@]} -gt 0 ]; then
      cmd_apply "${args[@]}"
    fi
    return 0
  fi

  cp "$TEMPLATE" "$MANIFEST"
  echo "✓ $MANIFEST créé depuis template"

  if [ ${#args[@]} -gt 0 ]; then
    cmd_apply "${args[@]}"
  else
    _merge_play_console
  fi
}

cmd_apply() {
  _need_jq
  _need_manifest

  local package="" name="" project_id="" module="" website=""
  local play_dev="" play_app="" firebase_app_id="" storage_bucket=""
  local gradle_google_services="" main_activity="" keystore_alias=""
  local require_wear=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --package) package="${2:?}"; shift 2 ;;
      --name) name="${2:?}"; shift 2 ;;
      --project-id) project_id="${2:?}"; shift 2 ;;
      --module) module="${2:?}"; shift 2 ;;
      --website) website="${2:?}"; shift 2 ;;
      --play-developer-id) play_dev="${2:?}"; shift 2 ;;
      --play-app-id) play_app="${2:?}"; shift 2 ;;
      --firebase-android-app-id) firebase_app_id="${2:?}"; shift 2 ;;
      --storage-bucket) storage_bucket="${2:?}"; shift 2 ;;
      --google-services) gradle_google_services="${2:?}"; shift 2 ;;
      --main-activity) main_activity="${2:?}"; shift 2 ;;
      --keystore-alias) keystore_alias="${2:?}"; shift 2 ;;
      --require-wear-screenshots) require_wear="${2:?}"; shift 2 ;;
      -h|--help)
        echo "apply — met à jour des champs + fill-urls + merge-play-console"
        echo "  --package --name --project-id --module --website"
        echo "  --play-developer-id --play-app-id --firebase-android-app-id"
        echo "  --storage-bucket --google-services --main-activity --keystore-alias"
        echo "  --require-wear-screenshots true|false"
        exit 0
        ;;
      *) echo "Option inconnue: $1" >&2; exit 2 ;;
    esac
  done

  _merge_play_console

  local filter='.'
  if [ -n "$package" ]; then
    filter+=" | .project.package = \$package"
  fi
  if [ -n "$name" ]; then
    filter+=" | .project.name = \$name"
    filter+=" | .build.keystoreDn = (\"CN=\" + \$name + \", OU=GeoKing, O=GeoKing, L=Paris, C=FR\")"
    filter+=" | .build.signInLogTag = (\$name + \"SignIn\")"
  fi
  if [ -n "$project_id" ]; then
    filter+=" | .project.id = \$project_id"
    if [ -z "$storage_bucket" ]; then
      filter+=" | .project.storageBucket = (\$project_id + \".firebasestorage.app\")"
    fi
  fi
  if [ -n "$storage_bucket" ]; then
    filter+=" | .project.storageBucket = \$storage_bucket"
  fi
  if [ -n "$firebase_app_id" ]; then
    filter+=" | .project.firebaseAndroidAppId = \$firebase_app_id"
  fi
  if [ -n "$play_dev" ]; then
    filter+=" | .urls.play.developerId = \$play_dev"
  fi
  if [ -n "$play_app" ]; then
    filter+=" | .urls.play.appId = \$play_app"
  fi
  if [ -n "$gradle_google_services" ]; then
    filter+=" | .build.googleServices = \$gs"
  fi
  if [ -n "$main_activity" ]; then
    filter+=" | .build.mainActivity = \$main_activity"
  fi
  if [ -n "$keystore_alias" ]; then
    filter+=" | .build.keystoreAlias = \$keystore_alias"
  fi
  if [ -n "$require_wear" ]; then
    filter+=" | .build.playStore.requireWearScreenshots = (\$require_wear == \"true\")"
  fi
  if [ -n "$website" ]; then
    filter+=" | .playConsole.contact.website = \$website"
    filter+=" | .playConsole.contact.privacyPolicyUrl = (\$website | sub(\"/$\";\"\") + \"/privacy\")"
    filter+=" | .urls.website = ((.urls.website // {}) + {home: \$website, policy: (\$website | sub(\"/$\";\"\") + \"/privacy.html\"), terms: (\$website | sub(\"/$\";\"\") + \"/terms.html\")})"
  fi

  jq \
    --arg package "$package" \
    --arg name "$name" \
    --arg project_id "$project_id" \
    --arg storage_bucket "$storage_bucket" \
    --arg firebase_app_id "$firebase_app_id" \
    --arg play_dev "$play_dev" \
    --arg play_app "$play_app" \
    --arg gs "$gradle_google_services" \
    --arg main_activity "$main_activity" \
    --arg keystore_alias "$keystore_alias" \
    --arg require_wear "$require_wear" \
    --arg website "$website" \
    "$filter" "$MANIFEST" | _write_json

  if [ -n "$module" ]; then
    case "$module" in
      :*) ;;
      *) module=":$module" ;;
    esac
    _apply_module_defaults "$module" <"$MANIFEST" | _write_json
  fi

  # If website not set but package is, derive https://<slug>.geoking.fr when placeholders remain
  if [ -z "$website" ] && [ -n "$package" ]; then
    local slug site
    slug="$(_slug_from_package "$package")"
    site="https://${slug}.geoking.fr"
    if jq -e '.playConsole.contact.website | test("APP\\.geoking|TODO|^$")' "$MANIFEST" >/dev/null 2>&1; then
      jq --arg website "$site" '
        .playConsole.contact.website = $website
        | .playConsole.contact.privacyPolicyUrl = ($website + "/privacy")
        | .urls.website = ((.urls.website // {}) + {
            home: $website,
            policy: ($website + "/privacy.html"),
            terms: ($website + "/terms.html")
          })
      ' "$MANIFEST" | _write_json
    fi
  fi

  cmd_fill_urls
  echo "✓ $MANIFEST mis à jour"
}

cmd_fill_urls() {
  _need_jq
  _need_manifest
  _fill_urls_filter <"$MANIFEST" | _write_json
  echo "✓ urls.firebase / urls.gcp / urls.play régénérées"
}

cmd_merge_play_console() {
  _need_jq
  _need_manifest
  if jq -e '.playConsole.appType' "$MANIFEST" >/dev/null 2>&1; then
    echo "· playConsole déjà présent"
    return 0
  fi
  _merge_play_console
}

cmd_set() {
  _need_jq
  _need_manifest
  local path="${1:?usage: set <jq-path> <value>}"
  local value="${2:?}"
  # path like .project.id — ensure leading dot
  case "$path" in
    .*) ;;
    *) path=".$path" ;;
  esac
  jq --arg v "$value" "$path = \$v" "$MANIFEST" | _write_json
  echo "✓ $path = $value"
}

cmd_set_json() {
  _need_jq
  _need_manifest
  local path="${1:?usage: set-json <jq-path> <json>}"
  local raw="${2:?}"
  case "$path" in
    .*) ;;
    *) path=".$path" ;;
  esac
  jq --argjson v "$raw" "$path = \$v" "$MANIFEST" | _write_json
  echo "✓ $path = $raw"
}

cmd_get() {
  _need_jq
  _need_manifest
  local path="${1:?usage: get <jq-path>}"
  case "$path" in
    .*) ;;
    *) path=".$path" ;;
  esac
  jq -r "$path" "$MANIFEST"
}

cmd_show() {
  _need_jq
  _need_manifest
  jq . "$MANIFEST"
}

cmd_path() {
  _resolve_root
  echo "$MANIFEST"
}

cmd_validate() {
  _need_jq
  _need_manifest
  local errors=0
  local warn=0

  check_str() {
    local path="$1" label="${2:-$1}"
    local v
    v="$(jq -r "$path // empty" "$MANIFEST")"
    if [ -z "$v" ] || [[ "$v" == TODO* ]] || [[ "$v" == PLAY_* ]] || [[ "$v" == my-* ]] || [[ "$v" == *APP.geoking* ]]; then
      echo "✗ $label manquant ou placeholder ($v)"
      errors=$((errors + 1))
    else
      echo "✓ $label"
    fi
  }

  check_opt() {
    local path="$1" label="${2:-$1}"
    local v
    v="$(jq -r "$path // empty" "$MANIFEST")"
    if [ -z "$v" ] || [[ "$v" == TODO* ]] || [[ "$v" == PLAY_* ]] || [[ "$v" == my-* ]]; then
      echo "· $label encore placeholder ($v)"
      warn=$((warn + 1))
    else
      echo "✓ $label"
    fi
  }

  echo "Manifest: $MANIFEST"
  check_str '.project.package' 'project.package'
  check_str '.project.name' 'project.name'
  check_opt '.project.id' 'project.id'
  check_opt '.project.firebaseAndroidAppId' 'project.firebaseAndroidAppId'
  check_str '.build.gradleModule' 'build.gradleModule'
  check_str '.build.googleServices' 'build.googleServices'
  check_opt '.urls.play.developerId' 'urls.play.developerId'
  check_opt '.urls.play.appId' 'urls.play.appId'

  if jq -e '.playConsole.appType' "$MANIFEST" >/dev/null 2>&1; then
    echo "✓ playConsole présent"
    check_opt '.playConsole.category' 'playConsole.category'
    check_opt '.playConsole.contact.email' 'playConsole.contact.email'
  else
    echo "· playConsole absent — ./scripts/project-manifest.sh merge-play-console"
    warn=$((warn + 1))
  fi

  if [ "$errors" -gt 0 ]; then
    echo
    echo "Échec: $errors champ(s) requis manquant(s), $warn warning(s)" >&2
    return 1
  fi
  echo
  echo "OK ($warn warning(s) optionnels)"
}

usage() {
  cat <<'EOF'
project-manifest — crée / met à jour scripts/project.manifest.json

  init     [--package PKG] [--name NAME] [--project-id ID] [--module :composeApp]
           [--website URL] [--force]
  apply    mêmes flags + --play-developer-id --play-app-id
           --firebase-android-app-id --storage-bucket --google-services
           --main-activity --keystore-alias --require-wear-screenshots true|false
  fill-urls
  merge-play-console
  set      <jq-path> <string>
  set-json <jq-path> <json>
  get      <jq-path>
  show
  path
  validate

Exemples:
  ./scripts/project-manifest.sh init --package fr.geoking.myapp --name MyApp --module :androidApp
  ./scripts/project-manifest.sh apply --project-id myapp-499318 --play-developer-id 123 --play-app-id 456
  ./scripts/project-manifest.sh set .playConsole.contact.email hello@geoking.fr
  ./scripts/project-manifest.sh validate
EOF
}

main() {
  _resolve_root
  local cmd="${1:-}"
  [ -n "$cmd" ] || { usage; exit 2; }
  shift || true

  # For most commands we can load project-env if manifest already exists
  case "$cmd" in
    init|path|help|-h|--help) ;;
    *)
      if [ -f "$MANIFEST" ]; then
        export GK_PROJECT_ROOT="$ROOT"
        # shellcheck disable=SC2034
        GK_MANIFEST_LOADED=""
        gk_project_init 2>/dev/null || true
      fi
      ;;
  esac

  case "$cmd" in
    init) cmd_init "$@" ;;
    apply|update) cmd_apply "$@" ;;
    fill-urls) cmd_fill_urls ;;
    merge-play-console) cmd_merge_play_console ;;
    set) cmd_set "$@" ;;
    set-json) cmd_set_json "$@" ;;
    get) cmd_get "$@" ;;
    show) cmd_show ;;
    path) cmd_path ;;
    validate|check) cmd_validate ;;
    help|-h|--help) usage ;;
    *)
      echo "Commande inconnue: $cmd" >&2
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"

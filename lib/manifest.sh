#!/usr/bin/env bash
# Load scripts/project.manifest.json into exported shell variables.
set -euo pipefail

[[ -n "${GEOKING_MANIFEST_LIB_LOADED:-}" ]] && return 0
GEOKING_MANIFEST_LIB_LOADED=1

geoking_manifest_jq() {
  local json="$1" filter="$2"
  jq -r "$filter" "$json"
}

geoking_manifest_export() {
  printf 'export %s=%q\n' "$1" "$2"
}

geoking_manifest_load() {
  local json="${1:?manifest json path required}"
  [ -f "$json" ] || {
    echo "project.manifest.json introuvable: $json" >&2
    return 1
  }
  command -v jq >/dev/null 2>&1 || {
    echo "jq est requis pour lire project.manifest.json (brew install jq)" >&2
    return 1
  }

  local pkg
  pkg="$(geoking_manifest_jq "$json" '.project.package')"

  geoking_manifest_export PROJECT_ID "$(geoking_manifest_jq "$json" '.project.id')"
  geoking_manifest_export PROJECT_NAME "$(geoking_manifest_jq "$json" '.project.name')"
  geoking_manifest_export APP_PACKAGE "$pkg"
  geoking_manifest_export APP_ID "$pkg"
  geoking_manifest_export FIREBASE_CONSOLE "$(geoking_manifest_jq "$json" '.urls.firebase.console')"
  geoking_manifest_export FIREBASE_PROJECT "$(geoking_manifest_jq "$json" '.urls.firebase.settings')"
  geoking_manifest_export FIREBASE_AUTH_GOOGLE "$(geoking_manifest_jq "$json" '.urls.firebase.authProviders')"
  geoking_manifest_export FIREBASE_AUTH_USERS "$(geoking_manifest_jq "$json" '.urls.firebase.authUsers')"
  geoking_manifest_export GCP_CONSOLE "$(geoking_manifest_jq "$json" '.urls.gcp.console')"
  geoking_manifest_export GCP_CREDENTIALS "$(geoking_manifest_jq "$json" '.urls.gcp.credentials')"
  geoking_manifest_export GCP_OAUTH_CONSENT "$(geoking_manifest_jq "$json" '.urls.gcp.oauthConsent')"
  geoking_manifest_export GCP_PLAY_API "$(geoking_manifest_jq "$json" '.urls.gcp.playDeveloperApi // .urls.gcp.console')"
  geoking_manifest_export GCP_SERVICE_ACCOUNTS "$(geoking_manifest_jq "$json" '.urls.gcp.serviceAccounts // .urls.gcp.console')"
  geoking_manifest_export PLAY_DEVELOPER_ID "$(geoking_manifest_jq "$json" '.urls.play.developerId')"
  geoking_manifest_export PLAY_APP_ID "$(geoking_manifest_jq "$json" '.urls.play.appId')"
  geoking_manifest_export PLAY_APP_DASHBOARD "$(geoking_manifest_jq "$json" '.urls.play.dashboard')"
  geoking_manifest_export PLAY_APP_INTEGRITY "$(geoking_manifest_jq "$json" '.urls.play.integrity')"
  geoking_manifest_export PLAY_INTEGRITY_HELP "$(geoking_manifest_jq "$json" '.urls.play.integrityHelp')"
  geoking_manifest_export PLAY_CONSOLE "$(geoking_manifest_jq "$json" '.urls.play.dashboard')"
  geoking_manifest_export GEMINI_API_KEYS "$(geoking_manifest_jq "$json" '.urls.gemini.apiKeys // "https://aistudio.google.com/apikey"')"
  geoking_manifest_export GITHUB_ACTIONS_SECRETS "$(geoking_manifest_jq "$json" '.urls.github.actionsSecrets // "https://github.com/settings/secrets/actions"')"

  geoking_manifest_export GRADLE_MODULE "$(geoking_manifest_jq "$json" '.build.gradleModule // ":composeApp"')"
  geoking_manifest_export GOOGLE_SERVICES_REL "$(geoking_manifest_jq "$json" '.build.googleServices // "composeApp/google-services.json"')"
  geoking_manifest_export KEY_ALIAS "$(geoking_manifest_jq "$json" '.build.keystoreAlias // "key0"')"
  geoking_manifest_export KEYSTORE_DN "$(geoking_manifest_jq "$json" '.build.keystoreDn // "CN=App, OU=GeoKing, O=GeoKing, L=Paris, C=FR"')"
  geoking_manifest_export SIGN_IN_LOG_TAG "$(geoking_manifest_jq "$json" '.build.signInLogTag // "AppSignIn"')"

  local main_activity
  main_activity="$(geoking_manifest_jq "$json" '.build.mainActivity // ".MainActivity"')"
  if [ "${main_activity#.}" != "$main_activity" ]; then
    geoking_manifest_export LAUNCH_ACTIVITY "${pkg}${main_activity}"
  else
    geoking_manifest_export LAUNCH_ACTIVITY "$main_activity"
  fi
}

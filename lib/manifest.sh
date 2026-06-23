#!/usr/bin/env bash
# Load scripts/project.manifest.json into exported shell variables.
set -euo pipefail

[[ -n "${GK_MANIFEST_LIB_LOADED:-}" ]] && return 0
GK_MANIFEST_LIB_LOADED=1

gk_manifest_jq() {
  local json="$1" filter="$2"
  jq -r "$filter" "$json"
}

gk_manifest_export() {
  printf 'export %s=%q\n' "$1" "$2"
}

gk_manifest_load() {
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
  pkg="$(gk_manifest_jq "$json" '.project.package')"

  gk_manifest_export PROJECT_ID "$(gk_manifest_jq "$json" '.project.id')"
  gk_manifest_export PROJECT_NAME "$(gk_manifest_jq "$json" '.project.name')"
  gk_manifest_export APP_PACKAGE "$pkg"
  gk_manifest_export APP_ID "$pkg"
  gk_manifest_export FIREBASE_CONSOLE "$(gk_manifest_jq "$json" '.urls.firebase.console')"
  gk_manifest_export FIREBASE_PROJECT "$(gk_manifest_jq "$json" '.urls.firebase.settings')"
  gk_manifest_export FIREBASE_AUTH_GOOGLE "$(gk_manifest_jq "$json" '.urls.firebase.authProviders')"
  gk_manifest_export FIREBASE_AUTH_USERS "$(gk_manifest_jq "$json" '.urls.firebase.authUsers')"
  gk_manifest_export GCP_CONSOLE "$(gk_manifest_jq "$json" '.urls.gcp.console')"
  gk_manifest_export GCP_CREDENTIALS "$(gk_manifest_jq "$json" '.urls.gcp.credentials')"
  gk_manifest_export GCP_OAUTH_CONSENT "$(gk_manifest_jq "$json" '.urls.gcp.oauthConsent')"
  gk_manifest_export GCP_PLAY_API "$(gk_manifest_jq "$json" '.urls.gcp.playDeveloperApi // .urls.gcp.console')"
  gk_manifest_export GCP_SERVICE_ACCOUNTS "$(gk_manifest_jq "$json" '.urls.gcp.serviceAccounts // .urls.gcp.console')"
  gk_manifest_export PLAY_DEVELOPER_ID "$(gk_manifest_jq "$json" '.urls.play.developerId')"
  gk_manifest_export PLAY_APP_ID "$(gk_manifest_jq "$json" '.urls.play.appId')"
  gk_manifest_export PLAY_APP_DASHBOARD "$(gk_manifest_jq "$json" '.urls.play.dashboard')"
  gk_manifest_export PLAY_APP_INTEGRITY "$(gk_manifest_jq "$json" '.urls.play.integrity')"
  gk_manifest_export PLAY_INTEGRITY_HELP "$(gk_manifest_jq "$json" '.urls.play.integrityHelp')"
  gk_manifest_export PLAY_CONSOLE "$(gk_manifest_jq "$json" '.urls.play.dashboard')"
  gk_manifest_export GEMINI_API_KEYS "$(gk_manifest_jq "$json" '.urls.gemini.apiKeys // "https://aistudio.google.com/apikey"')"
  gk_manifest_export GITHUB_ACTIONS_SECRETS "$(gk_manifest_jq "$json" '.urls.github.actionsSecrets // "https://github.com/settings/secrets/actions"')"

  gk_manifest_export GRADLE_MODULE "$(gk_manifest_jq "$json" '.build.gradleModule // ":composeApp"')"
  gk_manifest_export GOOGLE_SERVICES_REL "$(gk_manifest_jq "$json" '.build.googleServices // "composeApp/google-services.json"')"
  gk_manifest_export KEY_ALIAS "$(gk_manifest_jq "$json" '.build.keystoreAlias // "key0"')"
  gk_manifest_export KEYSTORE_DN "$(gk_manifest_jq "$json" '.build.keystoreDn // "CN=App, OU=GeoKing, O=GeoKing, L=Paris, C=FR"')"
  gk_manifest_export SIGN_IN_LOG_TAG "$(gk_manifest_jq "$json" '.build.signInLogTag // "AppSignIn"')"
  gk_manifest_export FIREBASE_ANDROID_APP_ID "$(gk_manifest_jq "$json" '.project.firebaseAndroidAppId // empty')"

  local main_activity
  main_activity="$(gk_manifest_jq "$json" '.build.mainActivity // ".MainActivity"')"
  if [ "${main_activity#.}" != "$main_activity" ]; then
    gk_manifest_export LAUNCH_ACTIVITY "${pkg}${main_activity}"
  else
    gk_manifest_export LAUNCH_ACTIVITY "$main_activity"
  fi
}

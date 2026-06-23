#!/usr/bin/env bash
# JDK 17 + Gradle resolution for local builds.
set -euo pipefail

[[ -n "${GEOKING_GRADLE_ENV_LOADED:-}" ]] && return 0
GEOKING_GRADLE_ENV_LOADED=1

geoking_resolve_java_home() {
  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/javac" ]; then
    return 0
  fi
  JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
  if [ -z "${JAVA_HOME:-}" ]; then
    local j
    for j in "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
             "$HOME/Library/Java/JavaVirtualMachines"/*/Contents/Home; do
      [ -x "$j/bin/javac" ] && { JAVA_HOME="$j"; break; }
    done
  fi
  [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/javac" ] || return 1
  export JAVA_HOME
}

geoking_resolve_gradle() {
  local root="$1"
  if [ -x "$root/gradlew" ]; then
    GRADLE=("$root/gradlew")
    return 0
  fi
  local g
  g="$(ls -d "$HOME"/.gradle/wrapper/dists/gradle-8.13-bin/*/gradle-8.13/bin/gradle 2>/dev/null | head -1)"
  [ -z "$g" ] && g="$(ls -d "$HOME"/.gradle/wrapper/dists/gradle-*/*/gradle-*/bin/gradle 2>/dev/null | sort -V | tail -1)"
  [ -z "$g" ] && g="$(command -v gradle 2>/dev/null || true)"
  [ -n "$g" ] || return 1
  GRADLE=("$g")
}

geoking_setup_build_env() {
  local root="$1"
  geoking_resolve_java_home || die "JDK introuvable. Définis JAVA_HOME (JDK 17)."
  ok "JDK : $JAVA_HOME"
  geoking_resolve_gradle "$root" || die "Gradle introuvable. Lance 'gradle wrapper --gradle-version 8.13' ou ouvre le projet dans Android Studio."
  ok "Gradle : ${GRADLE[*]}"
}

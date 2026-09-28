#!/usr/bin/env bash
# JDK + Gradle resolution for local builds.
set -euo pipefail

[[ -n "${GK_GRADLE_ENV_LOADED:-}" ]] && return 0
GK_GRADLE_ENV_LOADED=1

JAVA_VERSION="${JAVA_VERSION:-21}"

# True if $1/bin/java reports major version == JAVA_VERSION.
gk_java_home_is_major() {
  local home="$1"
  [ -x "${home}/bin/java" ] || return 1
  "${home}/bin/java" -version 2>&1 | head -1 | grep -Eq "version \"${JAVA_VERSION}([.\"]|$)"
}

gk_resolve_java_home() {
  local candidate=""
  local sdkman_root="${SDKMAN_DIR:-$HOME/.sdkman}/candidates/java"

  # 1) Keep ambient JAVA_HOME only if it is the requested major.
  if [ -n "${JAVA_HOME:-}" ] && gk_java_home_is_major "$JAVA_HOME"; then
    export JAVA_HOME
    return 0
  fi

  # 2) SDKMAN — preferred (macOS java_home often misses SDKMAN installs,
  #    and on this machine `java_home -v 21` wrongly returns OpenJDK 19).
  if [ -d "$sdkman_root" ]; then
    for candidate in \
      "$sdkman_root/${JAVA_VERSION}.0.2-open" \
      "$sdkman_root/current" \
      "$sdkman_root"/${JAVA_VERSION}*; do
      if gk_java_home_is_major "$candidate"; then
        export JAVA_HOME="$candidate"
        return 0
      fi
    done
  fi

  # 3) macOS java_home — always verify the reported major.
  if command -v /usr/libexec/java_home >/dev/null 2>&1; then
    candidate="$(/usr/libexec/java_home -v "$JAVA_VERSION" 2>/dev/null || true)"
    if [ -n "$candidate" ] && gk_java_home_is_major "$candidate"; then
      export JAVA_HOME="$candidate"
      return 0
    fi
  fi

  # 4) Common install locations
  for candidate in \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
    "$HOME/Library/Java/JavaVirtualMachines"/*/Contents/Home \
    /usr/lib/jvm/java-"${JAVA_VERSION}"-openjdk* \
    /usr/lib/jvm/temurin-"${JAVA_VERSION}"*; do
    if gk_java_home_is_major "$candidate"; then
      export JAVA_HOME="$candidate"
      return 0
    fi
  done

  return 1
}

gk_resolve_gradle() {
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

gk_setup_build_env() {
  local root="$1"
  gk_resolve_java_home || die "JDK introuvable. Définis JAVA_HOME (JDK $JAVA_VERSION)."
  export PATH="$JAVA_HOME/bin:$PATH"
  unset JDK_HOME
  ok "JDK : $JAVA_HOME"
  gk_resolve_gradle "$root" || die "Gradle introuvable. Lance 'gradle wrapper --gradle-version 8.13' ou ouvre le projet dans Android Studio."
  ok "Gradle : ${GRADLE[*]}"
}

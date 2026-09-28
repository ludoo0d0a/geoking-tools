#!/usr/bin/env bash
# Met à jour gradle/libs.versions.toml via nl.littlerobots.version-catalog-update.
#
# Usage:
#   ./scripts/update-version-catalog.sh
#   ./scripts/update-version-catalog.sh --interactive   # revue avant apply
#
set -euo pipefail

# shellcheck source=../lib/project-env.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/project-env.sh"
gk_project_init
cd "$ROOT"

# JDK 21 (évite les JDK ambient trop récents qui cassent le Kotlin DSL)
if [[ -z "${JAVA_HOME:-}" ]] || ! "$JAVA_HOME/bin/java" -version 2>&1 | grep -q '"21\.'; then
  if [[ -x "$HOME/.sdkman/candidates/java/21.0.2-open/bin/java" ]]; then
    export JAVA_HOME="$HOME/.sdkman/candidates/java/21.0.2-open"
  elif [[ -x "$HOME/.sdkman/candidates/java/current/bin/java" ]] \
    && "$HOME/.sdkman/candidates/java/current/bin/java" -version 2>&1 | grep -q '"21\.'; then
    export JAVA_HOME="$HOME/.sdkman/candidates/java/current"
  elif command -v /usr/libexec/java_home >/dev/null 2>&1; then
    export JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"
  fi
fi
[[ -n "${JAVA_HOME:-}" ]] || {
  echo "JDK 21 introuvable — exporte JAVA_HOME vers un JDK 21" >&2
  exit 1
}
export PATH="$JAVA_HOME/bin:$PATH"
unset JDK_HOME

INTERACTIVE=0
for arg in "$@"; do
  case "$arg" in
    -i|--interactive) INTERACTIVE=1 ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *)
      echo "Option inconnue: $arg (utilisez --interactive ou --help)" >&2
      exit 1
      ;;
  esac
done

echo "==> JAVA_HOME=$JAVA_HOME"
echo "==> Détection des mises à jour (versionCatalogUpdate)…"
if [[ "$INTERACTIVE" -eq 1 ]]; then
  ./gradlew versionCatalogUpdate --interactive
else
  ./gradlew versionCatalogUpdate
fi

echo "==> Application au TOML (versionCatalogApplyUpdates)…"
./gradlew versionCatalogApplyUpdates

echo "==> Diff catalog:"
git --no-pager diff -- gradle/libs.versions.toml || true
echo "OK — libs.versions.toml à jour."

#!/usr/bin/env bash
#
# Affiche l'usage GitHub Actions du mois (minutes facturables) et estime le
# reste de quota inclus selon le plan.
#
# L'ancien endpoint /settings/billing/actions (410 Gone) est remplacé par
# l'API billing usage consolidée :
#   GET /users/{user}/settings/billing/usage/summary?product=actions
#   GET /organizations/{org}/settings/billing/usage/summary?product=actions
#
# Usage :
#   ./bin/gh-quota.sh              # compte gh courant
#   ./bin/gh-quota.sh --user NAME
#   ./bin/gh-quota.sh --org ORG
#   ./bin/gh-quota.sh --month 2026-03
#   ./bin/gh-quota.sh --json
#   ./bin/gh-quota.sh --detail     # lignes d'usage brutes
#
# Prérequis : gh (scopes user ou admin:org), jq
#   gh auth refresh -h github.com -s user          # compte perso
#   gh auth refresh -h github.com -s admin:org     # organisation
#
set -euo pipefail

# shellcheck source=../lib/ui.sh
. "$(cd "$(dirname "$0")/../lib" && pwd)/ui.sh"

ACCOUNT_KIND=user   # user | org
ACCOUNT=""
YEAR=""
MONTH=""
JSON_OUT=false
DETAIL=false
# Minutes incluses / mois (runners standard, repos privés). Override: GK_ACTIONS_INCLUDED_MINUTES
INCLUDED_OVERRIDE="${GK_ACTIONS_INCLUDED_MINUTES:-}"

usage() {
  sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage ;;
    --user) ACCOUNT_KIND=user; ACCOUNT="${2:?}"; shift 2 ;;
    --org)  ACCOUNT_KIND=org;  ACCOUNT="${2:?}"; shift 2 ;;
    --month)
      # YYYY-MM
      [[ "${2:?}" =~ ^([0-9]{4})-([0-9]{1,2})$ ]] || die "--month attendu au format YYYY-MM"
      YEAR="${BASH_REMATCH[1]}"
      MONTH=$((10#${BASH_REMATCH[2]}))
      shift 2
      ;;
    --year)  YEAR="${2:?}"; shift 2 ;;
    --json)  JSON_OUT=true; shift ;;
    --detail) DETAIL=true; shift ;;
    *) die "Option inconnue : $1 (voir --help)" ;;
  esac
done

need gh
need jq

gh auth status >/dev/null 2>&1 || die "gh non authentifié — lance : gh auth login"

if [ -z "$ACCOUNT" ]; then
  ACCOUNT="$(gh api user --jq .login)"
  ACCOUNT_KIND=user
fi

if [ -z "$YEAR" ]; then YEAR="$(date +%Y)"; fi
if [ -z "$MONTH" ]; then MONTH="$(date +%-m)"; fi

# --- plan → minutes incluses -------------------------------------------------
included_for_plan() {
  case "${1:-}" in
    pro|Pro) echo 3000 ;;
    team|Team) echo 3000 ;;
    enterprise|business|Enterprise) echo 50000 ;;
    free|Free|"") echo 2000 ;;
    *) echo 2000 ;;
  esac
}

resolve_included() {
  if [ -n "$INCLUDED_OVERRIDE" ]; then
    echo "$INCLUDED_OVERRIDE"
    return
  fi
  if [ "$ACCOUNT_KIND" = user ]; then
    local plan
    plan="$(gh api "users/$ACCOUNT" --jq '.plan.name // empty' 2>/dev/null || true)"
    included_for_plan "$plan"
  else
    # Orgs Free=2000, Team=3000 — plan.name via /orgs/{org} n'est pas fiable ;
    # défaut Free, overridable via GK_ACTIONS_INCLUDED_MINUTES.
    echo 2000
  fi
}

# --- API path + scopes -------------------------------------------------------
api_path() {
  if [ "$ACCOUNT_KIND" = org ]; then
    printf 'organizations/%s/settings/billing/usage/summary' "$ACCOUNT"
  else
    printf 'users/%s/settings/billing/usage/summary' "$ACCOUNT"
  fi
}

detail_path() {
  if [ "$ACCOUNT_KIND" = org ]; then
    printf 'organizations/%s/settings/billing/usage' "$ACCOUNT"
  else
    printf 'users/%s/settings/billing/usage' "$ACCOUNT"
  fi
}

ensure_scope_hint() {
  local err="$1"
  if echo "$err" | grep -qi 'user scope\|"user" scope'; then
    warn "Scope manquant : user"
    code "gh auth refresh -h github.com -s user"
  elif echo "$err" | grep -qi 'admin:org'; then
    warn "Scope manquant : admin:org"
    code "gh auth refresh -h github.com -s admin:org"
  fi
}

fetch_detail() {
  local path qs
  path="$(detail_path)"
  qs="year=${YEAR}&month=${MONTH}"
  gh api "${path}?${qs}" 2>/dev/null || true
}

# Fetch outside $(...) so die()/exit propagates (command substitution = subshell).
_PATH="$(api_path)"
_TMP="$(mktemp)"
_ERR="$(mktemp)"
trap 'rm -f "$_TMP" "$_ERR"' EXIT

_fetch_ok=false
if gh api "${_PATH}?year=${YEAR}&month=${MONTH}&product=actions" >"$_TMP" 2>"$_ERR"; then
  _fetch_ok=true
elif gh api "${_PATH}?year=${YEAR}&month=${MONTH}&product=Actions" >"$_TMP" 2>"$_ERR"; then
  _fetch_ok=true
fi

if [ "$_fetch_ok" != true ]; then
  ensure_scope_hint "$(cat "$_ERR")"
  cat "$_ERR" >&2
  die "Impossible de lire le billing usage (${ACCOUNT_KIND}=${ACCOUNT})"
fi

SUMMARY_JSON="$(cat "$_TMP")"
INCLUDED="$(resolve_included)"

# Aggregate Actions SKUs (minutes / billable units).
AGG="$(jq -n --argjson s "$SUMMARY_JSON" --argjson incl "$INCLUDED" '
  ($s.usageItems // []) as $items
  | ($items
      | map(select((.product | ascii_downcase) | test("actions")))
      | map({
          sku: .sku,
          unit: .unitType,
          qty: (.netQuantity // .grossQuantity // 0),
          net: (.netAmount // 0),
          gross: (.grossAmount // 0)
        })
    ) as $rows
  | ($rows
      | map(select((.unit | ascii_downcase) | test("minute")))
      | map(.qty) | add // 0) as $used
  | {
      account: ($s.user // $s.organization // ""),
      period: {
        year: ($s.timePeriod.year // null),
        month: ($s.timePeriod.month // null)
      },
      included_minutes: $incl,
      used_minutes: $used,
      remaining_minutes: ([$incl - $used, 0] | max),
      percent_used: (if $incl > 0 then (($used / $incl) * 1000 | round / 10) else null end),
      by_sku: $rows,
      note: "used_minutes = unités facturables minutes only (Linux×1, Windows×2, macOS×10). Storage listé à part. Public repos = gratuit."
    }
')"

if [ "$JSON_OUT" = true ]; then
  printf '%s\n' "$AGG"
  exit 0
fi

USED="$(jq -r '.used_minutes' <<<"$AGG")"
REMAIN="$(jq -r '.remaining_minutes' <<<"$AGG")"
PCT="$(jq -r '.percent_used // 0' <<<"$AGG")"
PERIOD="$(printf '%04d-%02d' "$YEAR" "$MONTH")"

head_ "GitHub Actions — quota ${PERIOD}"
ok "Compte : ${ACCOUNT_KIND}/${ACCOUNT}"
say "  Inclus (plan)     : ${INCLUDED} min  ${c_dim}(override: GK_ACTIONS_INCLUDED_MINUTES)${c_off}"
say "  Utilisé           : ${USED} min facturables"
if awk "BEGIN{exit !($PCT >= 90)}"; then
  fail "Restant          : ${REMAIN} min  (${PCT}% utilisé)"
elif awk "BEGIN{exit !($PCT >= 70)}"; then
  warn "Restant           : ${REMAIN} min  (${PCT}% utilisé)"
else
  ok "Restant           : ${REMAIN} min  (${PCT}% utilisé)"
fi

blank
subhead "Par SKU"
if [ "$(jq '.by_sku | length' <<<"$AGG")" = 0 ]; then
  hint "Aucune consommation Actions ce mois (ou product filter vide)."
else
  jq -r '.by_sku[] | "  \(.sku)\n     \(.qty) \(.unit)  —  net $\(.net)"' <<<"$AGG"
fi

blank
hint "UI billing : https://github.com/settings/billing"
hint "Repos de secours sans minutes : ./scripts/build-and-publish.sh"

if [ "$DETAIL" = true ]; then
  blank
  subhead "Détail (usage report)"
  DETAIL_JSON="$(fetch_detail)"
  if [ -z "$DETAIL_JSON" ] || [ "$DETAIL_JSON" = "null" ]; then
    warn "Pas de détail disponible"
  else
    jq -r '
      (.usageItems // [])
      | map(select((.product | ascii_downcase) | test("actions")))
      | sort_by(.date)
      | .[]
      | "  \(.date)  \(.sku)  qty=\(.quantity)  repo=\(.repositoryName // "-")"
    ' <<<"$DETAIL_JSON" || warn "Aucun item Actions dans le report"
  fi
fi

blank

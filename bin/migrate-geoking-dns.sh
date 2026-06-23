#!/usr/bin/env bash
# Migrate geoking.fr subdomains from Netlify hosting to Cloudflare Pages
# while DNS is still managed by Netlify (before NS cutover to Cloudflare).
#
# Project list: templates/project.manifest.json
# Netlify DNS reference: geoking.fr (DNS Records).csv (export Netlify)
#
# Usage:
#   NETLIFY_TOKEN in local.properties (or export) — User settings → Applications → PAT
#   geoking-tools/bin/migrate-geoking-dns.sh status
#   geoking-tools/bin/migrate-geoking-dns.sh migrate --dry-run
#   geoking-tools/bin/migrate-geoking-dns.sh migrate --site vincent
#   geoking-tools/bin/migrate-geoking-dns.sh migrate --all --verify
#
# From an app repo: ./scripts/migrate-geoking-dns.sh (wrapper → geoking-tools)
#
# Requires: curl, jq

set -euo pipefail

TOOLS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEOKING_TOOLS_ROOT="$TOOLS_ROOT"
# shellcheck source=../lib/geoking-dns.sh
. "$TOOLS_ROOT/lib/geoking-dns.sh"
geoking_dns_init_paths
geoking_dns_load_local_properties

PROJECTS_MANIFEST="${GEOKING_PROJECTS_MANIFEST}"
DNS_CSV="${GEOKING_DNS_CSV}"

DOMAIN="geoking.fr"
ZONE_ID="${NETLIFY_ZONE_ID:-geoking_fr}"
API="https://api.netlify.com/api/v1/dns_zones/${ZONE_ID}/dns_records"
TTL="${DNS_TTL:-300}"

DRY_RUN=false
VERIFY=false
ROLLBACK=false
SITE_FILTER=""
COMMAND=""

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  echo
  echo "Commands:"
  echo "  status     Compare API vs CSV reference + manifest Pages targets (default)"
  echo "  reference  Print manifest + CSV Netlify targets"
  echo "  migrate    Point records to Cloudflare Pages (or back to Netlify with --rollback)"
  echo
  echo "Options:"
  echo "  --site NAME     DNS subdomain (e.g. vincent, www) — see project.manifest.json"
  echo "  --all           All projects with dns.subdomain (default for migrate)"
  echo "  --dry-run       Show planned changes without writing"
  echo "  --verify        After migrate, curl -I each https URL"
  echo "  --rollback      Restore Netlify targets from CSV (NETLIFY records)"
  echo "  -h, --help      This help"
  echo
  echo "Environment:"
  echo "  NETLIFY_TOKEN              local.properties or env (except dry-run / reference)"
  echo "  NETLIFY_ZONE_ID            Default: geoking_fr"
  echo "  GEOKING_PROJECTS_MANIFEST  Default: templates/project.manifest.json"
  echo "  GEOKING_DNS_CSV            Netlify export CSV"
  echo "  DNS_TTL                    Default: 300"
  echo "  MIGRATE_TARGET_<site>      Per-subdomain pages.dev override"
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

load_projects_manifest() {
  [ -f "$PROJECTS_MANIFEST" ] || die "projects manifest not found: $PROJECTS_MANIFEST"
  need_cmd jq
  local count
  count="$(jq '[.projects[] | select(.dns.subdomain != null)] | length' "$PROJECTS_MANIFEST")"
  [ "$count" -gt 0 ] || die "no projects with dns.subdomain in $PROJECTS_MANIFEST"
}

load_dns_csv() {
  [ -f "$DNS_CSV" ] || die "DNS CSV not found: $DNS_CSV"
}

manifest_jq() {
  jq -r "$@" "$PROJECTS_MANIFEST"
}

fqdn_for_site() {
  local site="$1"
  if [ "$site" = "@" ]; then
    printf '%s' "$DOMAIN"
  else
    printf '%s.%s' "$site" "$DOMAIN"
  fi
}

# Netlify rollback target from exported CSV (NETLIFY row, skips NETLIFYv6).
csv_netlify_target() {
  local site="$1"
  local fqdn
  fqdn="$(fqdn_for_site "$site")"
  awk -F',' -v fqdn="$fqdn" '
    NR > 1 && $3 == "\"NETLIFY\"" {
      gsub(/^"|"$/, "", $1)
      gsub(/^"|"$/, "", $4)
      if ($1 == fqdn) {
        print $4
        exit
      }
    }
  ' "$DNS_CSV"
}

auth_header() {
  [ -n "${NETLIFY_TOKEN:-}" ] || die "NETLIFY_TOKEN is not set"
  printf 'Authorization: Bearer %s' "$NETLIFY_TOKEN"
}

all_sites() {
  manifest_jq '[.projects[] | select(.dns.subdomain != null) | .dns.subdomain] | .[]' | sort
}

project_name_for_site() {
  local site="$1"
  manifest_jq --arg site "$site" '
    [.projects[] | select(.dns.subdomain == $site) | .name] | first // empty
  '
}

pages_target_for_site() {
  local site="$1"
  local var="MIGRATE_TARGET_${site}"
  if [ -n "${!var:-}" ]; then
    printf '%s' "${!var}"
    return
  fi
  local target
  target="$(manifest_jq --arg site "$site" '
    [.projects[] | select(.dns.subdomain == $site) |
      .dns.pagesHost // (.dns.pagesProject + ".pages.dev")] | first // empty
  ')"
  [ -n "$target" ] || die "unknown subdomain: $site (not in $PROJECTS_MANIFEST)"
  printf '%s' "$target"
}

site_is_known() {
  local site="$1"
  [ "$(manifest_jq --arg site "$site" '[.projects[] | select(.dns.subdomain == $site)] | length')" -gt 0 ]
}

sites_to_process() {
  if [ -n "$SITE_FILTER" ]; then
    printf '%s\n' "$SITE_FILTER"
    return
  fi
  all_sites
}

dns_record_type_for_target() {
  local target="$1"
  case "$target" in
    *.netlify.app) printf 'NETLIFY' ;;
    *)             printf 'CNAME' ;;
  esac
}

api_get_records() {
  curl -fsS -H "$(auth_header)" -H 'Accept: application/json' "$API"
}

api_records_for_site() {
  local site="$1"
  echo "$RECORDS_JSON" | jq -c --arg site "$site" --arg domain "$DOMAIN" '
    [.[] | select(
      (.hostname == $site or .hostname == ($site + "." + $domain) or
       ($site == "@" and (.hostname == $domain or .hostname == "@")))
      and (.type == "CNAME" or .type == "NETLIFY" or .type == "NETLIFYv6" or .type == "A")
    )]
  '
}

print_site_status() {
  local site="$1"
  local pages_target csv_netlify fqdn project_name
  pages_target="$(pages_target_for_site "$site")"
  csv_netlify="$(csv_netlify_target "$site")"
  fqdn="$(fqdn_for_site "$site")"
  project_name="$(project_name_for_site "$site")"

  local matches
  matches="$(api_records_for_site "$site")"

  local count
  count="$(echo "$matches" | jq 'length')"

  printf '  %s' "$fqdn"
  [ -n "$project_name" ] && printf ' (%s)' "$project_name"
  printf '\n'
  printf '    pages target : %s\n' "$pages_target"
  if [ -n "$csv_netlify" ]; then
    printf '    csv netlify  : %s\n' "$csv_netlify"
  else
    printf '    csv netlify  : (not in CSV — new site?)\n'
  fi

  if [ "$count" -eq 0 ]; then
    printf '    api          : (no record)\n'
    return
  fi

  echo "$matches" | jq -r '.[] |
    "    api          : \(.type) → \(.value)  ttl=\(.ttl // "—")" +
    (if .type == "CNAME" and .value == "'"$pages_target"'" then "  ✓ on Cloudflare Pages" else "" end) +
    (if .type == "NETLIFY" and .value == "'"$csv_netlify"'" then "  ✓ on Netlify (CSV match)" else "" end)
  '
}

cmd_reference() {
  load_projects_manifest
  load_dns_csv

  echo "Projects: ${PROJECTS_MANIFEST}"
  echo "Netlify DNS reference: ${DNS_CSV}"
  echo

  while IFS= read -r site; do
    local fqdn pages csv_netlify name
    fqdn="$(fqdn_for_site "$site")"
    pages="$(pages_target_for_site "$site")"
    csv_netlify="$(csv_netlify_target "$site")"
    name="$(project_name_for_site "$site")"
    printf '  %-22s  %-12s  csv: %-28s  →  %s\n' \
      "$fqdn" "$name" "${csv_netlify:-—}" "$pages"
  done < <(sites_to_process)
}

cmd_status() {
  need_cmd curl
  load_projects_manifest
  load_dns_csv

  echo "Zone: ${ZONE_ID} (${DOMAIN})"
  echo "Projects: ${PROJECTS_MANIFEST}"
  echo "CSV:  ${DNS_CSV}"
  echo

  if [ "$DRY_RUN" = true ] && [ -z "${NETLIFY_TOKEN:-}" ]; then
    cmd_reference
    return
  fi

  if [ "$DRY_RUN" = false ]; then
    [ -n "${NETLIFY_TOKEN:-}" ] || die "NETLIFY_TOKEN is not set (or use --dry-run)"
  fi

  if [ -n "${NETLIFY_TOKEN:-}" ]; then
    RECORDS_JSON="$(api_get_records)"
  else
    RECORDS_JSON="[]"
  fi

  while IFS= read -r site; do
    print_site_status "$site"
    echo
  done < <(sites_to_process)
}

migrate_site() {
  local site="$1"
  local target="$2"
  local fqdn
  fqdn="$(fqdn_for_site "$site")"
  local record_type
  record_type="$(dns_record_type_for_target "$target")"

  local matches
  matches="$(api_records_for_site "$site")"

  local already_ok
  if [ "$record_type" = "NETLIFY" ]; then
    already_ok="$(echo "$matches" | jq -r --arg target "$target" '
      [.[] | select(.type == "NETLIFY" and .value == $target)] | length > 0
    ')"
  else
    already_ok="$(echo "$matches" | jq -r --arg target "$target" '
      [.[] | select(.type == "CNAME" and .value == $target)] | length > 0
    ')"
  fi

  if [ "$already_ok" = "true" ]; then
    echo "skip: ${fqdn} already ${record_type} → ${target}"
    return 0
  fi

  local to_delete
  to_delete="$(echo "$matches" | jq -c '[.[] | select(.value != "'"$target"'") | {id, type, value}]')"

  echo "plan: ${fqdn}"
  echo "  create: ${record_type} ${site} → ${target} (ttl=${TTL})"
  echo "$to_delete" | jq -r '.[] | "  delete: \(.type) → \(.value) (id=\(.id))"'

  if [ "$DRY_RUN" = true ]; then
    return 0
  fi

  local create_payload
  create_payload="$(jq -nc --arg hostname "$site" --arg value "$target" --arg type "$record_type" --argjson ttl "$TTL" \
    '{type: $type, hostname: $hostname, value: $value, ttl: $ttl}')"

  curl -fsS -X POST "$API" \
    -H "$(auth_header)" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -d "$create_payload" >/dev/null

  echo "  created ${record_type}"

  local id type value
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    id="$(echo "$line" | jq -r '.id')"
    type="$(echo "$line" | jq -r '.type')"
    value="$(echo "$line" | jq -r '.value')"
    curl -fsS -X DELETE "${API}/${id}" -H "$(auth_header)" >/dev/null
    echo "  deleted ${type} → ${value}"
  done < <(echo "$to_delete" | jq -c '.[]')

  echo "done: ${fqdn} → ${target}"
}

verify_site() {
  local site="$1"
  local url
  if [ "$site" = "@" ]; then
    url="https://${DOMAIN}"
  else
    url="https://${site}.${DOMAIN}"
  fi
  local code
  code="$(curl -fsSIL -o /dev/null -w '%{http_code}' --max-time 15 "$url" 2>/dev/null || echo "000")"
  if [[ "$code" =~ ^2|^3 ]]; then
    echo "verify OK: ${url} (${code})"
  else
    echo "verify WARN: ${url} (HTTP ${code}) — propagation or Pages custom domain may still be pending"
  fi
}

cmd_migrate() {
  need_cmd curl
  load_projects_manifest
  load_dns_csv

  if [ "$DRY_RUN" = false ]; then
    [ -n "${NETLIFY_TOKEN:-}" ] || die "NETLIFY_TOKEN is not set"
    RECORDS_JSON="$(api_get_records)"
  else
    if [ -n "${NETLIFY_TOKEN:-}" ]; then
      RECORDS_JSON="$(api_get_records)"
    else
      RECORDS_JSON="[]"
    fi
  fi

  echo "Zone: ${ZONE_ID} (${DOMAIN})"
  echo "Projects: ${PROJECTS_MANIFEST}"
  echo "CSV:  ${DNS_CSV}"
  [ "$DRY_RUN" = true ] && echo "mode: dry-run"
  [ "$ROLLBACK" = true ] && echo "mode: rollback → Netlify (from CSV)"
  echo

  while IFS= read -r site; do
    local target
    if [ "$ROLLBACK" = true ]; then
      target="$(csv_netlify_target "$site")"
      [ -n "$target" ] || die "no NETLIFY row in CSV for site: $site ($(fqdn_for_site "$site"))"
    else
      target="$(pages_target_for_site "$site")"
    fi

    if [ "$DRY_RUN" = true ] && [ "$RECORDS_JSON" = "[]" ]; then
      echo "plan: $(fqdn_for_site "$site") → ${target} (no API — token missing)"
      continue
    fi

    migrate_site "$site" "$target"
    echo
  done < <(sites_to_process)

  if [ "$VERIFY" = true ] && [ "$DRY_RUN" = false ] && [ "$ROLLBACK" = false ]; then
    echo "HTTPS checks:"
    while IFS= read -r site; do
      verify_site "$site"
    done < <(sites_to_process)
  fi
}

# --- parse args ---
if [ $# -eq 0 ]; then
  COMMAND="status"
fi

while [ $# -gt 0 ]; do
  case "$1" in
    status|reference|migrate)
      COMMAND="$1"
      shift
      ;;
    --site)
      [ $# -ge 2 ] || die "--site requires a value"
      SITE_FILTER="$2"
      shift 2
      ;;
    --all)
      SITE_FILTER=""
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --verify)
      VERIFY=true
      shift
      ;;
    --rollback)
      ROLLBACK=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1 (try --help)"
      ;;
  esac
done

[ -n "$COMMAND" ] || COMMAND="status"

load_projects_manifest

if [ -n "$SITE_FILTER" ] && ! site_is_known "$SITE_FILTER"; then
  die "unknown site: $SITE_FILTER (known: $(all_sites | tr '\n' ' '))"
fi

case "$COMMAND" in
  status)    cmd_status ;;
  reference) cmd_reference ;;
  migrate)   cmd_migrate ;;
  *)         die "unknown command: $COMMAND" ;;
esac

#!/usr/bin/env bash
# Phase 3 — prepare Cloudflare DNS zone + Pages custom domains before NS cutover.
#
# Prerequisites:
#   - geoking.fr added to Cloudflare (zone may be pending until NS change)
#   - Phase 1–2 done: sites deployed on Cloudflare Pages
#   - CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID in local.properties (or export)
#
# Usage:
#   export CLOUDFLARE_API_TOKEN="..."
#   export CLOUDFLARE_ACCOUNT_ID="..."
#   bin/cutover-cloudflare-dns.sh plan
#   bin/cutover-cloudflare-dns.sh apply --dry-run
#   bin/cutover-cloudflare-dns.sh pages --dry-run
#   bin/cutover-cloudflare-dns.sh apply-all --dry-run
#   bin/cutover-cloudflare-dns.sh nameservers
#
# NS change at registrar remains manual; run `nameservers` for the values.

set -euo pipefail

TOOLS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEOKING_TOOLS_ROOT="$TOOLS_ROOT"
# shellcheck source=../lib/geoking-dns.sh
. "$TOOLS_ROOT/lib/geoking-dns.sh"
geoking_dns_init_paths
geoking_dns_load_local_properties

CF_API="https://api.cloudflare.com/client/v4"
DRY_RUN=false
INCLUDE_LEGACY=false
SITE_FILTER=""
COMMAND=""

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
  echo
  echo "Commands:"
  echo "  plan         Show DNS + Pages plan (default)"
  echo "  apply        Upsert DNS records in Cloudflare zone"
  echo "  pages        Attach custom domains to Cloudflare Pages projects"
  echo "  nameservers  Print Cloudflare NS (+ dig check if resolvable)"
  echo "  apply-all    apply + pages + nameservers summary"
  echo
  echo "Options:"
  echo "  --site NAME       One manifest subdomain only"
  echo "  --include-legacy  Also CNAME log/logbook → Netlify (from CSV)"
  echo "  --dry-run         Print actions without API writes"
  echo "  -h, --help"
  echo
  echo "Environment:"
  echo "  CLOUDFLARE_API_TOKEN       local.properties or env"
  echo "  CLOUDFLARE_ACCOUNT_ID      local.properties or env"
  echo "  CLOUDFLARE_ZONE_ID     Optional (auto lookup by zone name)"
  echo "  GEOKING_DOMAIN         Default: geoking.fr"
}

cf_need_auth() {
  [ -n "${CLOUDFLARE_API_TOKEN:-}" ] || geoking_dns_die "CLOUDFLARE_API_TOKEN is not set"
  [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] || geoking_dns_die "CLOUDFLARE_ACCOUNT_ID is not set"
}

cf_api() {
  local method="$1"
  local path="$2"
  shift 2
  curl -fsS -X "$method" "${CF_API}${path}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@"
}

cf_api_json() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  if [ -n "$body" ]; then
    cf_api "$method" "$path" -d "$body"
  else
    cf_api "$method" "$path"
  fi
}

cf_resolve_zone_id() {
  if [ -n "${CLOUDFLARE_ZONE_ID:-}" ]; then
    printf '%s' "$CLOUDFLARE_ZONE_ID"
    return
  fi
  local resp
  resp="$(cf_api_json GET "/zones?name=${GEOKING_DOMAIN}&status=active,pending,initializing")"
  local zone_id
  zone_id="$(echo "$resp" | jq -r '[.result[] | select(.name == "'"$GEOKING_DOMAIN"'") | .id] | first // empty')"
  [ -n "$zone_id" ] || geoking_dns_die "Cloudflare zone not found for ${GEOKING_DOMAIN} — add the site in the dashboard first"
  printf '%s' "$zone_id"
}

sites_to_process() {
  if [ -n "$SITE_FILTER" ]; then
    printf '%s\n' "$SITE_FILTER"
    return
  fi
  geoking_dns_all_sites
}

plan_pages_cname_records() {
  local site
  while IFS= read -r site; do
    local name target
    name="$(geoking_dns_cf_name_for_site "$site")"
    target="$(geoking_dns_pages_target_for_site "$site")"
    jq -nc --arg name "$name" --arg content "$target" \
      '{kind:"pages",name:$name,type:"CNAME",content:$content,proxied:true,ttl:1}'
  done < <(sites_to_process)

  if [ -z "$SITE_FILTER" ]; then
    local apex_target
    apex_target="$(geoking_dns_pages_target_for_site "www")"
    jq -nc --arg content "$apex_target" \
      '{kind:"pages",name:"@",type:"CNAME",content:$content,proxied:true,ttl:1}'
  fi
}

plan_apex_service_records() {
  geoking_dns_csv_apex_records_jsonl | while IFS= read -r row; do
    [ -z "$row" ] && continue
    echo "$row" | jq -c '. + {kind:"service"}'
  done
}

plan_legacy_records() {
  [ "$INCLUDE_LEGACY" = true ] || return 0
  geoking_dns_csv_legacy_hosts_jsonl
}

cmd_plan() {
  geoking_dns_load_projects_manifest
  geoking_dns_load_dns_csv

  echo "Zone: ${GEOKING_DOMAIN}"
  echo "Manifest: ${GEOKING_PROJECTS_MANIFEST}"
  echo "CSV: ${GEOKING_DNS_CSV}"
  echo
  echo "Cloudflare Pages CNAMEs (proxied):"
  plan_pages_cname_records | jq -r '"  \(.name)  CNAME  →  \(.content)"'
  echo
  echo "Service records from CSV (apex):"
  local service_rows
  service_rows="$(plan_apex_service_records | jq -s '.')"
  if [ "$(echo "$service_rows" | jq 'length')" -eq 0 ]; then
    echo "  (none)"
  else
    echo "$service_rows" | jq -r '.[] | "  \(.type)  @  →  \(.value)  priority=\(.priority // "—")"'
  fi
  echo
  if [ "$INCLUDE_LEGACY" = true ]; then
    echo "Legacy Netlify CNAMEs:"
    plan_legacy_records | jq -r '"  \(.fqdn)  CNAME  →  \(.value)"'
  else
    echo "Legacy hosts (log, logbook, …): skipped — use --include-legacy to keep on Netlify"
  fi
  echo
  echo "Pages custom domains:"
  while IFS= read -r site; do
    printf '  %s (%s)\n' "$(geoking_dns_fqdn_for_site "$site")" "$(geoking_dns_pages_project_for_site "$site")"
  done < <(sites_to_process)
}

cf_list_records() {
  local zone_id="$1"
  cf_api_json GET "/zones/${zone_id}/dns_records?per_page=500"
}

cf_find_record_id() {
  local zone_id="$1"
  local type="$2"
  local name="$3"
  local content="${4:-}"
  local full_name
  if [ "$name" = "@" ]; then
    full_name="$GEOKING_DOMAIN"
  else
    full_name="${name}.${GEOKING_DOMAIN}"
  fi
  local resp
  resp="$(cf_list_records "$zone_id")"
  if [ -n "$content" ]; then
    echo "$resp" | jq -r --arg type "$type" --arg name "$full_name" --arg content "$content" '
      [.result[] | select(.type == $type and .name == $name and .content == $content) | .id] | first // empty
    '
  else
    echo "$resp" | jq -r --arg type "$type" --arg name "$full_name" '
      [.result[] | select(.type == $type and .name == $name) | .id] | first // empty
    '
  fi
}

cf_upsert_record() {
  local zone_id="$1"
  local type="$2"
  local name="$3"
  local content="$4"
  local proxied="${5:-false}"
  local ttl="${6:-1}"
  local priority="${7:-}"

  local full_name
  if [ "$name" = "@" ]; then
    full_name="$GEOKING_DOMAIN"
  else
    full_name="${name}.${GEOKING_DOMAIN}"
  fi

  local existing_id
  existing_id="$(cf_find_record_id "$zone_id" "$type" "$name" "$content")"

  local payload
  if [ "$type" = "MX" ]; then
    payload="$(jq -nc --arg type "$type" --arg name "$name" --arg content "$content" \
      --argjson ttl "$ttl" --argjson priority "${priority:-10}" \
      '{type:$type,name:$name,content:$content,ttl:$ttl,priority:$priority}')"
  elif [ "$type" = "CNAME" ]; then
    payload="$(jq -nc --arg type "$type" --arg name "$name" --arg content "$content" \
      --argjson ttl "$ttl" --argjson proxied "$proxied" \
      '{type:$type,name:$name,content:$content,ttl:$ttl,proxied:$proxied}')"
  else
    payload="$(jq -nc --arg type "$type" --arg name "$name" --arg content "$content" \
      --argjson ttl "$ttl" \
      '{type:$type,name:$name,content:$content,ttl:$ttl}')"
  fi

  echo "  ${type} ${name} → ${content}"

  if [ "$DRY_RUN" = true ]; then
    [ -n "$existing_id" ] && echo "    would PATCH ${existing_id}" || echo "    would POST"
    return 0
  fi

  local resp
  if [ -n "$existing_id" ]; then
    resp="$(cf_api_json PATCH "/zones/${zone_id}/dns_records/${existing_id}" "$payload")"
    echo "    updated ${existing_id}"
  else
    resp="$(cf_api_json POST "/zones/${zone_id}/dns_records" "$payload")"
    echo "    created $(echo "$resp" | jq -r '.result.id')"
  fi

  if ! echo "$resp" | jq -e '.success == true' >/dev/null; then
    echo "$resp" | jq '.' >&2
    geoking_dns_die "Cloudflare API error for ${full_name}"
  fi
}

cmd_apply() {
  geoking_dns_need_cmd jq
  geoking_dns_need_cmd curl
  cf_need_auth
  geoking_dns_load_projects_manifest
  geoking_dns_load_dns_csv

  local zone_id
  zone_id="$(cf_resolve_zone_id)"
  echo "Cloudflare zone: ${GEOKING_DOMAIN} (${zone_id})"
  [ "$DRY_RUN" = true ] && echo "mode: dry-run"
  echo

  echo "Pages CNAMEs:"
  plan_pages_cname_records | while IFS= read -r row; do
    [ -z "$row" ] && continue
    local name type content
    name="$(echo "$row" | jq -r '.name')"
    type="$(echo "$row" | jq -r '.type')"
    content="$(echo "$row" | jq -r '.content')"
    cf_upsert_record "$zone_id" "$type" "$name" "$content" true 1
  done

  echo
  echo "Service records (MX/TXT):"
  plan_apex_service_records | while IFS= read -r row; do
    [ -z "$row" ] && continue
    local fqdn cf_name type value ttl priority
    fqdn="$(echo "$row" | jq -r '.fqdn')"
    cf_name="$(geoking_dns_cf_name_for_fqdn "$fqdn")"
    type="$(echo "$row" | jq -r '.type')"
    value="$(echo "$row" | jq -r '.value')"
    ttl="$(echo "$row" | jq -r '.ttl')"
    priority="$(echo "$row" | jq -r '.priority')"
    cf_upsert_record "$zone_id" "$type" "$cf_name" "$value" false "$ttl" "$priority"
  done

  if [ "$INCLUDE_LEGACY" = true ]; then
    echo
    echo "Legacy Netlify CNAMEs:"
    plan_legacy_records | while IFS= read -r row; do
      [ -z "$row" ] && continue
      local cf_name value
      cf_name="$(geoking_dns_cf_name_for_fqdn "$(echo "$row" | jq -r '.fqdn')")"
      value="$(echo "$row" | jq -r '.value')"
      cf_upsert_record "$zone_id" "CNAME" "$cf_name" "$value" true 1
    done
  fi
}

cf_pages_domain_exists() {
  local project="$1"
  local domain="$2"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    "${CF_API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${project}/domains/${domain}")"
  [ "$code" = "200" ]
}

cf_attach_pages_domain() {
  local project="$1"
  local domain="$2"

  echo "  ${domain} → project ${project}"

  if cf_pages_domain_exists "$project" "$domain"; then
    echo "    skip: already attached"
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "    would POST custom domain"
    return 0
  fi

  local resp
  resp="$(cf_api_json POST "/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${project}/domains" \
    "$(jq -nc --arg name "$domain" '{name:$name}')")"

  if echo "$resp" | jq -e '.success == true' >/dev/null; then
    echo "    attached"
  else
    echo "$resp" | jq '.' >&2
    geoking_dns_die "failed to attach ${domain} to ${project}"
  fi
}

cmd_pages() {
  geoking_dns_need_cmd jq
  geoking_dns_need_cmd curl
  cf_need_auth
  geoking_dns_load_projects_manifest

  echo "Cloudflare Pages custom domains:"
  [ "$DRY_RUN" = true ] && echo "mode: dry-run"

  while IFS= read -r site; do
    local fqdn project
    fqdn="$(geoking_dns_fqdn_for_site "$site")"
    project="$(geoking_dns_pages_project_for_site "$site")"
    [ -n "$project" ] || geoking_dns_die "missing pagesProject for site: $site"
    cf_attach_pages_domain "$project" "$fqdn"
  done < <(sites_to_process)

  if [ -z "$SITE_FILTER" ]; then
    local apex_project
    apex_project="$(geoking_dns_pages_project_for_site "www")"
    cf_attach_pages_domain "$apex_project" "$GEOKING_DOMAIN"
  fi
}

cmd_nameservers() {
  geoking_dns_need_cmd jq
  geoking_dns_need_cmd curl
  cf_need_auth

  local zone_id
  zone_id="$(cf_resolve_zone_id)"
  local resp
  resp="$(cf_api_json GET "/zones/${zone_id}")"

  echo "Cloudflare zone: ${GEOKING_DOMAIN} (${zone_id})"
  echo "Status: $(echo "$resp" | jq -r '.result.status')"
  echo
  echo "Nameservers to set at your registrar:"
  echo "$resp" | jq -r '.result.name_servers[]' | sed 's/^/  /'
  echo
  echo "Current NS (public DNS):"
  if command -v dig >/dev/null 2>&1; then
    dig NS "$GEOKING_DOMAIN" +short | sed 's/^/  /' || true
  else
    echo "  (install dig to check propagation)"
  fi
  echo
  echo "After updating NS at the registrar, wait for propagation then remove ${GEOKING_DOMAIN} from Netlify."
}

cmd_apply_all() {
  cmd_apply
  echo
  cmd_pages
  echo
  cmd_nameservers
}

# --- parse args ---
if [ $# -eq 0 ]; then
  COMMAND="plan"
fi

while [ $# -gt 0 ]; do
  case "$1" in
    plan|apply|pages|nameservers|apply-all)
      COMMAND="$1"
      shift
      ;;
    --site)
      [ $# -ge 2 ] || geoking_dns_die "--site requires a value"
      SITE_FILTER="$2"
      shift 2
      ;;
    --include-legacy)
      INCLUDE_LEGACY=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      geoking_dns_die "unknown argument: $1 (try --help)"
      ;;
  esac
done

geoking_dns_init_paths
geoking_dns_load_projects_manifest

if [ -n "$SITE_FILTER" ] && ! geoking_dns_site_is_known "$SITE_FILTER"; then
  geoking_dns_die "unknown site: $SITE_FILTER (known: $(geoking_dns_all_sites | tr '\n' ' '))"
fi

case "$COMMAND" in
  plan)       cmd_plan ;;
  apply)      cmd_apply ;;
  pages)      cmd_pages ;;
  nameservers) cmd_nameservers ;;
  apply-all)  cmd_apply_all ;;
  *)          geoking_dns_die "unknown command: $COMMAND" ;;
esac

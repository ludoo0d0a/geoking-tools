#!/usr/bin/env bash
# Shared helpers for geoking.fr DNS migration scripts.
set -euo pipefail

[[ -n "${GEOKING_DNS_LIB_LOADED:-}" ]] && return 0
GEOKING_DNS_LIB_LOADED=1

geoking_dns_tools_root() {
  if [ -n "${GEOKING_TOOLS_ROOT:-}" ]; then
    printf '%s' "$GEOKING_TOOLS_ROOT"
    return
  fi
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$lib_dir/.." && pwd
}

geoking_dns_init_paths() {
  local root
  root="$(geoking_dns_tools_root)"
  GEOKING_DOMAIN="${GEOKING_DOMAIN:-geoking.fr}"
  GEOKING_PROJECTS_MANIFEST="${GEOKING_PROJECTS_MANIFEST:-$root/templates/project.manifest.json}"
  GEOKING_DNS_CSV="${GEOKING_DNS_CSV:-$root/geoking.fr (DNS Records).csv}"
}

# Load NETLIFY_TOKEN / CLOUDFLARE_* from local.properties when not already exported.
# Search order: GK_PROJECT_ROOT, GEOKING_LOCAL_PROPERTIES, walk up from $PWD.
geoking_dns_load_local_properties() {
  local lp="" dir

  if [ -n "${GK_PROJECT_ROOT:-}" ] && [ -f "${GK_PROJECT_ROOT}/local.properties" ]; then
    lp="${GK_PROJECT_ROOT}/local.properties"
  elif [ -n "${GEOKING_LOCAL_PROPERTIES:-}" ] && [ -f "$GEOKING_LOCAL_PROPERTIES" ]; then
    lp="$GEOKING_LOCAL_PROPERTIES"
  else
    dir="$PWD"
    while [ "$dir" != "/" ]; do
      if [ -f "$dir/local.properties" ]; then
        lp="$dir/local.properties"
        break
      fi
      dir="$(dirname "$dir")"
    done
  fi

  [ -n "$lp" ] || return 0

  geoking_dns_import_prop() {
    local key="$1"
    local current=""
    case "$key" in
      NETLIFY_TOKEN) current="${NETLIFY_TOKEN:-}" ;;
      CLOUDFLARE_API_TOKEN) current="${CLOUDFLARE_API_TOKEN:-}" ;;
      CLOUDFLARE_ACCOUNT_ID) current="${CLOUDFLARE_ACCOUNT_ID:-}" ;;
      *) return 0 ;;
    esac
    [ -n "$current" ] && return 0
    local val
    val="$(grep -E "^${key}=" "$lp" 2>/dev/null | cut -d= -f2- | head -1 || true)"
    [ -n "$val" ] && export "${key}=${val}"
  }

  geoking_dns_import_prop NETLIFY_TOKEN
  geoking_dns_import_prop CLOUDFLARE_API_TOKEN
  geoking_dns_import_prop CLOUDFLARE_ACCOUNT_ID
}

geoking_dns_die() {
  echo "error: $*" >&2
  exit 1
}

geoking_dns_need_cmd() {
  command -v "$1" >/dev/null 2>&1 || geoking_dns_die "missing dependency: $1"
}

geoking_dns_load_projects_manifest() {
  geoking_dns_init_paths
  [ -f "$GEOKING_PROJECTS_MANIFEST" ] || geoking_dns_die "projects manifest not found: $GEOKING_PROJECTS_MANIFEST"
  geoking_dns_need_cmd jq
  local count
  count="$(jq '[.projects[] | select(.dns.subdomain != null)] | length' "$GEOKING_PROJECTS_MANIFEST")"
  [ "$count" -gt 0 ] || geoking_dns_die "no projects with dns.subdomain in $GEOKING_PROJECTS_MANIFEST"
}

geoking_dns_load_dns_csv() {
  geoking_dns_init_paths
  [ -f "$GEOKING_DNS_CSV" ] || geoking_dns_die "DNS CSV not found: $GEOKING_DNS_CSV"
}

geoking_dns_manifest_jq() {
  jq -r "$@" "$GEOKING_PROJECTS_MANIFEST"
}

geoking_dns_fqdn_for_site() {
  local site="$1"
  if [ "$site" = "@" ]; then
    printf '%s' "$GEOKING_DOMAIN"
  else
    printf '%s.%s' "$site" "$GEOKING_DOMAIN"
  fi
}

# Cloudflare record name: apex → @, else subdomain label.
geoking_dns_cf_name_for_fqdn() {
  local fqdn="$1"
  if [ "$fqdn" = "$GEOKING_DOMAIN" ]; then
    printf '@'
  else
    printf '%s' "${fqdn%.${GEOKING_DOMAIN}}"
  fi
}

geoking_dns_cf_name_for_site() {
  local site="$1"
  if [ "$site" = "@" ]; then
    printf '@'
  else
    printf '%s' "$site"
  fi
}

geoking_dns_all_sites() {
  geoking_dns_manifest_jq '[.projects[] | select(.dns.subdomain != null) | .dns.subdomain] | .[]' | sort
}

geoking_dns_project_name_for_site() {
  local site="$1"
  geoking_dns_manifest_jq --arg site "$site" '
    [.projects[] | select(.dns.subdomain == $site) | .name] | first // empty
  '
}

geoking_dns_pages_project_for_site() {
  local site="$1"
  geoking_dns_manifest_jq --arg site "$site" '
    [.projects[] | select(.dns.subdomain == $site) | .dns.pagesProject] | first // empty
  '
}

geoking_dns_pages_target_for_site() {
  local site="$1"
  local var="MIGRATE_TARGET_${site}"
  if [ -n "${!var:-}" ]; then
    printf '%s' "${!var}"
    return
  fi
  local target
  target="$(geoking_dns_manifest_jq --arg site "$site" '
    [.projects[] | select(.dns.subdomain == $site) |
      .dns.pagesHost // (.dns.pagesProject + ".pages.dev")] | first // empty
  ')"
  [ -n "$target" ] || geoking_dns_die "unknown subdomain: $site (not in $GEOKING_PROJECTS_MANIFEST)"
  printf '%s' "$target"
}

geoking_dns_site_is_known() {
  local site="$1"
  [ "$(geoking_dns_manifest_jq --arg site "$site" '[.projects[] | select(.dns.subdomain == $site)] | length')" -gt 0 ]
}

geoking_dns_csv_netlify_target() {
  local fqdn="$1"
  awk -F',' -v fqdn="$fqdn" '
    NR > 1 && $3 == "\"NETLIFY\"" {
      gsub(/^"|"$/, "", $1)
      gsub(/^"|"$/, "", $4)
      if ($1 == fqdn) {
        print $4
        exit
      }
    }
  ' "$GEOKING_DNS_CSV"
}

# Emit JSON lines: {fqdn,type,value,ttl,priority}
geoking_dns_csv_apex_records_jsonl() {
  awk -F',' -v domain="$GEOKING_DOMAIN" '
    NR > 1 && $1 == "\"" domain "\"" && ($3 == "\"MX\"" || $3 == "\"TXT\"") {
      gsub(/^"|"$/, "", $3)
      gsub(/^"|"$/, "", $4)
      ttl = $2
      gsub(/^"|"$/, "", ttl)
      priority = ($3 == "MX" ? 10 : 0)
      printf "{\"fqdn\":\"%s\",\"type\":\"%s\",\"value\":\"%s\",\"ttl\":%s,\"priority\":%s}\n",
        domain, $3, $4, ttl, priority
    }
  ' "$GEOKING_DNS_CSV" | awk '
    BEGIN { mx = 0 }
    /"type":"MX"/ { mx++; sub(/"priority":[0-9]+/, "\"priority\":" (mx == 1 ? 10 : 20)); print; next }
    { print }
  '
}

# NETLIFY hosts in CSV not covered by manifest projects (e.g. log, logbook).
geoking_dns_csv_legacy_hosts_jsonl() {
  geoking_dns_need_cmd jq
  local manifest_fqdns
  manifest_fqdns="$(
    geoking_dns_manifest_jq --arg domain "$GEOKING_DOMAIN" '
      [.projects[] | select(.dns.subdomain != null) |
        if .dns.subdomain == "@" then $domain else (.dns.subdomain + "." + $domain) end]
    '
  )"
  awk -F',' -v domain="$GEOKING_DOMAIN" '
    NR > 1 && $3 == "\"NETLIFY\"" {
      gsub(/^"|"$/, "", $1)
      gsub(/^"|"$/, "", $4)
      gsub(/^"|"$/, "", $2)
      if ($1 != domain && $1 ~ ("\\." domain "$")) {
        print $1 "\t" $4 "\t" $2
      }
    }
  ' "$GEOKING_DNS_CSV" | while IFS=$'\t' read -r fqdn target ttl; do
    if ! echo "$manifest_fqdns" | grep -Fxq "$fqdn"; then
      jq -nc --arg fqdn "$fqdn" --arg target "$target" --argjson ttl "${ttl:-3600}" \
        '{fqdn:$fqdn,type:"CNAME",value:$target,ttl:$ttl,proxied:true,legacy:true}'
    fi
  done
}

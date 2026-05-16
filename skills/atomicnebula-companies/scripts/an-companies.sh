#!/bin/bash
#
# Atomic Nebula Companies CLI Helper
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR_PHYSICAL="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR_PHYSICAL}/../../.." && pwd -P)"

RESOLVE_ENV_CANDIDATES=(
  "${SCRIPT_DIR_PHYSICAL}/../../shared/resolve-env.sh"
  "${REPO_ROOT}/skills/shared/resolve-env.sh"
  "${SCRIPT_DIR}/../../shared/resolve-env.sh"
  "${REPO_ROOT}/openclaw-skills/shared/resolve-env.sh"
)

RESOLVE_ENV_SH=""
for candidate in "${RESOLVE_ENV_CANDIDATES[@]}"; do
  if [[ -f "${candidate}" ]]; then
    RESOLVE_ENV_SH="${candidate}"
    break
  fi
done

if [[ -z "${RESOLVE_ENV_SH}" ]]; then
  echo "Error: could not find resolve-env.sh from ${SCRIPT_DIR}" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "${RESOLVE_ENV_SH}"

eval "$(extract_env_flag "$@")"
resolve_an_env "$ENV_ARG"

CURL_BASE=(-s -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json")
ENV_PREFIX=$(print_env_prefix)

usage() {
  cat << 'USAGE'
Atomic Nebula Companies CLI

Usage: an-companies.sh [--env <workspace>] <command> [options]

Commands:
  list                  List companies
  get <companyId>       Get one company
  create                Create a company (--confirm yes required)
  update <companyId>    Update a company (--confirm yes required)
  delete <companyId>    Delete a company (--confirm yes required)

List Options:
  --search <term>       Search companies
  --limit <n>           Page size (default: 50, max: 100)
  --cursor <token>      Opaque cursor from the previous response

Write Options:
  --name <value>        (required for create)
  --domain <value>
  --website <value>
  --phone <value>
  --email <value>
  --industry <value>
  --city <value>
  --state <value>
  --country <value>
  --tag <value>         (repeatable)
  --confirm yes
USAGE
}

require_api_key() {
  if [[ -z "${API_KEY:-}" ]]; then
    echo "Error: No API key found for workspace '${AN_ENV}'." >&2
    echo "Set ATOMICNEBULA_API_KEY or configure ${AN_ASSISTANT_CONFIG_FILE}." >&2
    exit 1
  fi
}

require_confirm() {
  local confirm="$1"
  if [[ "$confirm" != "yes" ]]; then
    echo "Error: write command requires --confirm yes" >&2
    exit 1
  fi
}

append_query_param() {
  local query="$1"
  local key="$2"
  local value="$3"
  if [[ -z "$value" ]]; then
    echo "$query"
    return
  fi
  local encoded
  encoded=$(printf '%s' "$value" | jq -sRr @uri)
  if [[ -z "$query" ]]; then
    echo "?${key}=${encoded}"
  else
    echo "${query}&${key}=${encoded}"
  fi
}

json_body() {
  local tags_json="[]"
  if [[ ${#TAGS[@]} -gt 0 ]]; then
    tags_json=$(printf '%s\n' "${TAGS[@]}" | jq -R . | jq -s .)
  fi
  jq -n \
    --arg name "${NAME:-}" \
    --arg domain "${DOMAIN:-}" \
    --arg website "${WEBSITE:-}" \
    --arg phone "${PHONE:-}" \
    --arg email "${EMAIL:-}" \
    --arg industry "${INDUSTRY:-}" \
    --arg city "${CITY:-}" \
    --arg state "${STATE:-}" \
    --arg country "${COUNTRY:-}" \
    --argjson tags "$tags_json" \
    '{
      name: (if $name == "" then null else $name end),
      domain: (if $domain == "" then null else $domain end),
      website: (if $website == "" then null else $website end),
      phone: (if $phone == "" then null else $phone end),
      email: (if $email == "" then null else $email end),
      industry: (if $industry == "" then null else $industry end),
      city: (if $city == "" then null else $city end),
      state: (if $state == "" then null else $state end),
      country: (if $country == "" then null else $country end),
      tags: (if ($tags | length) == 0 then null else $tags end)
    } | with_entries(select(.value != null))'
}

parse_company_fields() {
  NAME=""
  DOMAIN=""
  WEBSITE=""
  PHONE=""
  EMAIL=""
  INDUSTRY=""
  CITY=""
  STATE=""
  COUNTRY=""
  TAGS=()
  CONFIRM=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) NAME="$2"; shift 2 ;;
      --domain) DOMAIN="$2"; shift 2 ;;
      --website) WEBSITE="$2"; shift 2 ;;
      --phone) PHONE="$2"; shift 2 ;;
      --email) EMAIL="$2"; shift 2 ;;
      --industry) INDUSTRY="$2"; shift 2 ;;
      --city) CITY="$2"; shift 2 ;;
      --state) STATE="$2"; shift 2 ;;
      --country) COUNTRY="$2"; shift 2 ;;
      --tag) TAGS+=("$2"); shift 2 ;;
      --confirm) CONFIRM="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
}

list_companies() {
  local search=""
  local limit="50"
  local cursor=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --search) search="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      --cursor) cursor="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  local query=""
  query=$(append_query_param "$query" "limit" "$limit")
  query=$(append_query_param "$query" "cursor" "$cursor")
  query=$(append_query_param "$query" "search" "$search")

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Listing companies from ${BASE_URL}" >&2
  curl "${CURL_BASE[@]}" "${BASE_URL}/api/v1/atomicnebula/companies${query}" | jq .
}

get_company() {
  local company_id="${1:-}"
  if [[ -z "$company_id" ]]; then
    echo "Error: company ID is required" >&2
    exit 1
  fi
  curl "${CURL_BASE[@]}" "${BASE_URL}/api/v1/atomicnebula/companies/${company_id}" | jq .
}

create_company() {
  parse_company_fields "$@"
  require_confirm "$CONFIRM"
  if [[ -z "$NAME" ]]; then
    echo "Error: --name is required" >&2
    exit 1
  fi
  json_body | curl "${CURL_BASE[@]}" -X POST --data @- "${BASE_URL}/api/v1/atomicnebula/companies" | jq .
}

update_company() {
  local company_id="${1:-}"
  if [[ -z "$company_id" ]]; then
    echo "Error: company ID is required" >&2
    exit 1
  fi
  shift
  parse_company_fields "$@"
  require_confirm "$CONFIRM"
  json_body | curl "${CURL_BASE[@]}" -X PATCH --data @- "${BASE_URL}/api/v1/atomicnebula/companies/${company_id}" | jq .
}

delete_company() {
  local company_id="${1:-}"
  if [[ -z "$company_id" ]]; then
    echo "Error: company ID is required" >&2
    exit 1
  fi
  shift
  local confirm=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --confirm) confirm="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
  require_confirm "$confirm"
  curl "${CURL_BASE[@]}" -X DELETE "${BASE_URL}/api/v1/atomicnebula/companies/${company_id}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" || -z "${1:-}" ]]; then
  usage
  exit 0
fi

require_api_key

case "${1:-}" in
  list) shift; list_companies "$@" ;;
  get) shift; get_company "$@" ;;
  create) shift; create_company "$@" ;;
  update) shift; update_company "$@" ;;
  delete) shift; delete_company "$@" ;;
  *) echo "Error: unknown command '$1'" >&2; usage; exit 1 ;;
esac

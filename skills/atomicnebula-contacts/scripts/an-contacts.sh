#!/bin/bash
#
# Atomic Nebula Contacts CLI Helper
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
Atomic Nebula Contacts CLI

Usage: an-contacts.sh [--env <workspace>] <command> [options]

Commands:
  list                  List contacts
  get <contactId>       Get one contact
  create                Create a contact (--confirm yes required)
  update <contactId>    Update a contact (--confirm yes required)
  delete <contactId>    Delete a contact (--confirm yes required)

List Options:
  --search <term>       Search contacts
  --page <n>            Page number (default: 1)
  --page-size <n>       Page size (default: 50)

Write Options:
  --email <value>
  --first-name <value>
  --last-name <value>
  --phone <value>
  --job-title <value>
  --company-id <value>
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
  jq -n \
    --arg email "${EMAIL:-}" \
    --arg firstName "${FIRST_NAME:-}" \
    --arg lastName "${LAST_NAME:-}" \
    --arg phone "${PHONE:-}" \
    --arg jobTitle "${JOB_TITLE:-}" \
    --arg companyId "${COMPANY_ID:-}" \
    '{
      email: (if $email == "" then null else $email end),
      firstName: (if $firstName == "" then null else $firstName end),
      lastName: (if $lastName == "" then null else $lastName end),
      phone: (if $phone == "" then null else $phone end),
      jobTitle: (if $jobTitle == "" then null else $jobTitle end),
      companyId: (if $companyId == "" then null else $companyId end)
    } | with_entries(select(.value != null))'
}

parse_contact_fields() {
  EMAIL=""
  FIRST_NAME=""
  LAST_NAME=""
  PHONE=""
  JOB_TITLE=""
  COMPANY_ID=""
  CONFIRM=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --email) EMAIL="$2"; shift 2 ;;
      --first-name) FIRST_NAME="$2"; shift 2 ;;
      --last-name) LAST_NAME="$2"; shift 2 ;;
      --phone) PHONE="$2"; shift 2 ;;
      --job-title) JOB_TITLE="$2"; shift 2 ;;
      --company-id) COMPANY_ID="$2"; shift 2 ;;
      --confirm) CONFIRM="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
}

list_contacts() {
  local search=""
  local page_num="1"
  local page_size="50"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --search) search="$2"; shift 2 ;;
      --page) page_num="$2"; shift 2 ;;
      --page-size) page_size="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  local query=""
  query=$(append_query_param "$query" "pageNum" "$page_num")
  query=$(append_query_param "$query" "pageSize" "$page_size")
  query=$(append_query_param "$query" "search" "$search")

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Listing contacts from ${BASE_URL}" >&2
  curl "${CURL_BASE[@]}" "${BASE_URL}/api/v1/atomicnebula/contacts${query}" | jq .
}

get_contact() {
  local contact_id="${1:-}"
  if [[ -z "$contact_id" ]]; then
    echo "Error: contact ID is required" >&2
    exit 1
  fi
  curl "${CURL_BASE[@]}" "${BASE_URL}/api/v1/atomicnebula/contacts/${contact_id}" | jq .
}

create_contact() {
  parse_contact_fields "$@"
  require_confirm "$CONFIRM"
  if [[ -z "$EMAIL" ]]; then
    echo "Error: --email is required" >&2
    exit 1
  fi
  json_body | curl "${CURL_BASE[@]}" -X POST --data @- "${BASE_URL}/api/v1/atomicnebula/contacts" | jq .
}

update_contact() {
  local contact_id="${1:-}"
  if [[ -z "$contact_id" ]]; then
    echo "Error: contact ID is required" >&2
    exit 1
  fi
  shift
  parse_contact_fields "$@"
  require_confirm "$CONFIRM"
  json_body | curl "${CURL_BASE[@]}" -X PATCH --data @- "${BASE_URL}/api/v1/atomicnebula/contacts/${contact_id}" | jq .
}

delete_contact() {
  local contact_id="${1:-}"
  if [[ -z "$contact_id" ]]; then
    echo "Error: contact ID is required" >&2
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
  curl "${CURL_BASE[@]}" -X DELETE "${BASE_URL}/api/v1/atomicnebula/contacts/${contact_id}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" || -z "${1:-}" ]]; then
  usage
  exit 0
fi

require_api_key

case "${1:-}" in
  list) shift; list_contacts "$@" ;;
  get) shift; get_contact "$@" ;;
  create) shift; create_contact "$@" ;;
  update) shift; update_contact "$@" ;;
  delete) shift; delete_contact "$@" ;;
  *) echo "Error: unknown command '$1'" >&2; usage; exit 1 ;;
esac

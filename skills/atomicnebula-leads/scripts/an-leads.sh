#!/bin/bash
#
# Atomic Nebula Leads CLI Helper
#
# Supports lead list/get/create/update/delete through the Atomic Nebula
# external REST API. Write calls send X-Run-Id and log approval challenges
# for webhook correlation.
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

RUN_ID=$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "run-$(date +%s)-$$")
WRITE_RUNS_LOG="${HOME}/.openclaw/logs/write-runs.log"
CURL_BASE=(-s -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json")

usage() {
  cat << 'USAGE'
Atomic Nebula Leads CLI

Usage: an-leads.sh [--env <workspace>] <command> [options]

Commands:
  list                       List leads
  get <leadId>               Get one lead
  create                     Create a lead
  update <leadId>            Update a lead
  delete <leadId>            Delete a lead

Global Options:
  --env <env>                Target workspace slug (e.g., spider, dev, circeaurasupport)

list Options:
  --pipeline-id <id>
  --stage-id <id>
  --owner-id <userId>
  --team-id <id>
  --territory-id <id>
  --contact-id <id>
  --form-id <id>
  --source <value>
  --qualification-status <value>
  --search <term>
  --score-min <n>
  --score-max <n>
  --sort-by <field>
  --sort-order <asc|desc>
  --limit <n>
  --cursor <token>

create Options:
  --email <text>             Required
  --first-name <text>
  --last-name <text>
  --phone <text>
  --company <text>
  --job-title <text>
  --website <text>
  --contact-id <id>
  --pipeline-id <id>
  --stage-id <id>
  --owner-id <userId>
  --team-id <id>
  --territory-id <id>
  --source <value>
  --score <n>
  --qualification-status <value>
  --form-id <id>
  --utm-source <text>
  --utm-medium <text>
  --utm-campaign <text>
  --referrer-url <text>
  --landing-page-url <text>
  --tag <value>              Repeatable
  --tags <csv>               Comma-separated alternative

update Options:
  Same as create options, except --email is optional and nullable fields can be cleared with:
  --clear-company
  --clear-contact-id
  --clear-owner-id
  --clear-team-id
  --clear-territory-id

Examples:
  an-leads.sh list --search acme --limit 20
  an-leads.sh get LEAD-ID
  an-leads.sh create --email "prospect@example.com" --first-name "Pat" --last-name "Lee"
  an-leads.sh update LEAD-ID --qualification-status sql --score 75 --tag qualified
  an-leads.sh delete LEAD-ID
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" || -z "${1:-}" ]]; then
  usage
  exit 0
fi

if [[ -z "${API_KEY:-}" ]]; then
  echo "Error: No API key found for workspace '${AN_ENV}'. Check assistant workspace config or run skills/shared/an-env-list.sh" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required" >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required" >&2
  exit 1
fi

HTTP_CODE=""
BODY=""

split_response() {
  local full_response="$1"
  HTTP_CODE=$(echo "$full_response" | tail -1)
  BODY=$(echo "$full_response" | sed '$d')
}

record_approval() {
  local action="$1"
  local body="$2"
  local challenge_id
  challenge_id=$(echo "$body" | jq -r '.challengeId // .error.details.challengeId // empty' 2>/dev/null || true)
  mkdir -p "$(dirname "$WRITE_RUNS_LOG")"
  printf '{"timestamp":"%s","runId":"%s","challengeId":"%s","action":"%s","environment":"%s","pid":%d,"ppid":%d}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$RUN_ID" \
    "${challenge_id:-}" \
    "$action" \
    "$AN_ENV" \
    "$$" \
    "${PPID:-0}" \
    >> "$WRITE_RUNS_LOG"

  echo "Approval required."
  echo "Run ID: $RUN_ID"
  if [[ -n "${challenge_id:-}" ]]; then
    echo "Challenge ID: $challenge_id"
  fi
  echo ""
  echo "$body" | jq . 2>/dev/null || echo "$body"
}

is_approval_response() {
  local code="$1"
  local body="$2"
  if [[ "$code" == "402" || "$code" == "403" ]]; then
    if echo "$body" | grep -q '"APPROVAL_REQUIRED"' 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

request_json() {
  local method="$1"
  local url="$2"
  local body="${3:-}"
  local include_run_id="${4:-false}"

  local headers=("${CURL_BASE[@]}")
  if [[ "$include_run_id" == "true" ]]; then
    headers+=(-H "X-Run-Id: $RUN_ID")
  fi

  local response
  if [[ -n "$body" ]]; then
    response=$(curl "${headers[@]}" -w "\n%{http_code}" -X "$method" -d "$body" "$url")
  else
    response=$(curl "${headers[@]}" -w "\n%{http_code}" -X "$method" "$url")
  fi

  split_response "$response"
}

print_or_fail() {
  local action="${1:-}"

  if is_approval_response "$HTTP_CODE" "$BODY"; then
    record_approval "$action" "$BODY"
    return 0
  fi

  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
  if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
    exit 1
  fi
}

uri() {
  printf '%s' "$1" | jq -sRr @uri
}

append_array_value() {
  local json="$1"
  local key="$2"
  local value="$3"
  if [[ -z "$value" ]]; then
    echo "$json"
  else
    echo "$json" | jq --arg k "$key" --arg v "$value" '
      . + {($k): (((.[$k] // []) + [$v]) | map(select(. != "")) | unique)}
    '
  fi
}

merge_csv_into_array() {
  local current_json="$1"
  local key="$2"
  local csv="$3"
  if [[ -z "$csv" ]]; then
    echo "$current_json"
    return
  fi
  local csv_array
  csv_array=$(printf '%s' "$csv" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | jq -R . | jq -s .)
  echo "$current_json" | jq --arg k "$key" --argjson extra "$csv_array" '
    . + {($k): (((.[$k] // []) + $extra) | map(select(. != "")) | unique)}
  '
}

add_string_field() {
  local json="$1"
  local key="$2"
  local value="$3"
  if [[ -z "$value" ]]; then
    echo "$json"
  else
    echo "$json" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}'
  fi
}

add_number_field() {
  local json="$1"
  local key="$2"
  local value="$3"
  if [[ -z "$value" ]]; then
    echo "$json"
  else
    echo "$json" | jq --arg k "$key" --argjson v "$value" '. + {($k): $v}'
  fi
}

add_null_field() {
  local json="$1"
  local key="$2"
  echo "$json" | jq --arg k "$key" '. + {($k): null}'
}

build_list_url() {
  local url="${BASE_URL}/api/v1/atomicnebula/leads"
  local first=1

  add_query_param() {
    local key="$1"
    local value="$2"
    if [[ -n "$value" ]]; then
      if [[ $first -eq 1 ]]; then
        url+="?${key}=$(uri "$value")"
        first=0
      else
        url+="&${key}=$(uri "$value")"
      fi
    fi
  }

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pipeline-id) add_query_param "lifecyclePipelineId" "$2"; shift 2 ;;
      --stage-id) add_query_param "lifecycleStageId" "$2"; shift 2 ;;
      --owner-id) add_query_param "ownerId" "$2"; shift 2 ;;
      --team-id) add_query_param "teamId" "$2"; shift 2 ;;
      --territory-id) add_query_param "territoryId" "$2"; shift 2 ;;
      --contact-id) add_query_param "contactId" "$2"; shift 2 ;;
      --form-id) add_query_param "formId" "$2"; shift 2 ;;
      --source) add_query_param "source" "$2"; shift 2 ;;
      --qualification-status) add_query_param "qualificationStatus" "$2"; shift 2 ;;
      --search) add_query_param "search" "$2"; shift 2 ;;
      --score-min) add_query_param "scoreMin" "$2"; shift 2 ;;
      --score-max) add_query_param "scoreMax" "$2"; shift 2 ;;
      --sort-by) add_query_param "sortBy" "$2"; shift 2 ;;
      --sort-order) add_query_param "sortOrder" "$2"; shift 2 ;;
      --limit) add_query_param "limit" "$2"; shift 2 ;;
      --cursor) add_query_param "cursor" "$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  echo "$url"
}

build_lead_payload() {
  local require_email="$1"
  shift

  local email=""
  local first_name=""
  local last_name=""
  local phone=""
  local company=""
  local job_title=""
  local website=""
  local contact_id=""
  local pipeline_id=""
  local stage_id=""
  local owner_id=""
  local team_id=""
  local territory_id=""
  local source=""
  local score=""
  local qualification_status=""
  local form_id=""
  local utm_source=""
  local utm_medium=""
  local utm_campaign=""
  local referrer_url=""
  local landing_page_url=""
  local payload='{}'

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --email) email="$2"; shift 2 ;;
      --first-name) first_name="$2"; shift 2 ;;
      --last-name) last_name="$2"; shift 2 ;;
      --phone) phone="$2"; shift 2 ;;
      --company) company="$2"; shift 2 ;;
      --job-title) job_title="$2"; shift 2 ;;
      --website) website="$2"; shift 2 ;;
      --contact-id) contact_id="$2"; shift 2 ;;
      --pipeline-id) pipeline_id="$2"; shift 2 ;;
      --stage-id) stage_id="$2"; shift 2 ;;
      --owner-id) owner_id="$2"; shift 2 ;;
      --team-id) team_id="$2"; shift 2 ;;
      --territory-id) territory_id="$2"; shift 2 ;;
      --source) source="$2"; shift 2 ;;
      --score) score="$2"; shift 2 ;;
      --qualification-status) qualification_status="$2"; shift 2 ;;
      --form-id) form_id="$2"; shift 2 ;;
      --utm-source) utm_source="$2"; shift 2 ;;
      --utm-medium) utm_medium="$2"; shift 2 ;;
      --utm-campaign) utm_campaign="$2"; shift 2 ;;
      --referrer-url) referrer_url="$2"; shift 2 ;;
      --landing-page-url) landing_page_url="$2"; shift 2 ;;
      --tag) payload=$(append_array_value "$payload" "tags" "$2"); shift 2 ;;
      --tags) payload=$(merge_csv_into_array "$payload" "tags" "$2"); shift 2 ;;
      --clear-company) payload=$(add_null_field "$payload" "company"); shift ;;
      --clear-contact-id) payload=$(add_null_field "$payload" "contactId"); shift ;;
      --clear-owner-id) payload=$(add_null_field "$payload" "ownerId"); shift ;;
      --clear-team-id) payload=$(add_null_field "$payload" "teamId"); shift ;;
      --clear-territory-id) payload=$(add_null_field "$payload" "territoryId"); shift ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ "$require_email" == "true" && -z "$email" ]]; then
    echo "Error: --email is required" >&2
    exit 1
  fi

  payload=$(add_string_field "$payload" "email" "$email")
  payload=$(add_string_field "$payload" "firstName" "$first_name")
  payload=$(add_string_field "$payload" "lastName" "$last_name")
  payload=$(add_string_field "$payload" "phone" "$phone")
  if ! echo "$payload" | jq -e 'has("company")' >/dev/null 2>&1; then
    payload=$(add_string_field "$payload" "company" "$company")
  fi
  payload=$(add_string_field "$payload" "jobTitle" "$job_title")
  payload=$(add_string_field "$payload" "website" "$website")
  if ! echo "$payload" | jq -e 'has("contactId")' >/dev/null 2>&1; then
    payload=$(add_string_field "$payload" "contactId" "$contact_id")
  fi
  payload=$(add_string_field "$payload" "lifecyclePipelineId" "$pipeline_id")
  payload=$(add_string_field "$payload" "lifecycleStageId" "$stage_id")
  if ! echo "$payload" | jq -e 'has("ownerId")' >/dev/null 2>&1; then
    payload=$(add_string_field "$payload" "ownerId" "$owner_id")
  fi
  if ! echo "$payload" | jq -e 'has("teamId")' >/dev/null 2>&1; then
    payload=$(add_string_field "$payload" "teamId" "$team_id")
  fi
  if ! echo "$payload" | jq -e 'has("territoryId")' >/dev/null 2>&1; then
    payload=$(add_string_field "$payload" "territoryId" "$territory_id")
  fi
  payload=$(add_string_field "$payload" "source" "$source")
  payload=$(add_number_field "$payload" "score" "$score")
  payload=$(add_string_field "$payload" "qualificationStatus" "$qualification_status")
  payload=$(add_string_field "$payload" "formId" "$form_id")
  payload=$(add_string_field "$payload" "utmSource" "$utm_source")
  payload=$(add_string_field "$payload" "utmMedium" "$utm_medium")
  payload=$(add_string_field "$payload" "utmCampaign" "$utm_campaign")
  payload=$(add_string_field "$payload" "referrerUrl" "$referrer_url")
  payload=$(add_string_field "$payload" "landingPageUrl" "$landing_page_url")

  echo "$payload"
}

command_list() {
  local url
  url=$(build_list_url "$@")
  request_json "GET" "$url"
  print_or_fail "list"
}

command_get() {
  local lead_id="${1:-}"
  if [[ -z "$lead_id" ]]; then
    echo "Error: leadId is required" >&2
    exit 1
  fi
  request_json "GET" "${BASE_URL}/api/v1/atomicnebula/leads/${lead_id}"
  print_or_fail "get"
}

command_create() {
  local payload
  payload=$(build_lead_payload "true" "$@")
  request_json "POST" "${BASE_URL}/api/v1/atomicnebula/leads" "$payload" "true"
  print_or_fail "create"
}

command_update() {
  local lead_id="${1:-}"
  shift || true
  if [[ -z "$lead_id" ]]; then
    echo "Error: leadId is required" >&2
    exit 1
  fi
  local payload
  payload=$(build_lead_payload "false" "$@")
  if [[ "$payload" == "{}" ]]; then
    echo "Error: no update fields provided" >&2
    exit 1
  fi
  request_json "PATCH" "${BASE_URL}/api/v1/atomicnebula/leads/${lead_id}" "$payload" "true"
  print_or_fail "update"
}

command_delete() {
  local lead_id="${1:-}"
  if [[ -z "$lead_id" ]]; then
    echo "Error: leadId is required" >&2
    exit 1
  fi
  request_json "DELETE" "${BASE_URL}/api/v1/atomicnebula/leads/${lead_id}" "" "true"
  if [[ "$HTTP_CODE" == "204" ]]; then
    echo '{"success":true,"data":{"deleted":true}}' | jq .
    return
  fi
  print_or_fail "delete"
}

case "${1:-}" in
  list)
    shift
    command_list "$@"
    ;;
  get)
    shift
    command_get "$@"
    ;;
  create)
    shift
    command_create "$@"
    ;;
  update)
    shift
    command_update "$@"
    ;;
  delete)
    shift
    command_delete "$@"
    ;;
  *)
    echo "Error: Unknown command '${1:-}'" >&2
    usage
    exit 1
    ;;
esac

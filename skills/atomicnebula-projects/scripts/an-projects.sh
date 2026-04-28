#!/bin/bash
#
# Atomic Nebula Projects CLI Helper
#
# Supports project list/create/update/archive and schema discovery endpoints
# through the Atomic Nebula external REST API. Write calls send X-Run-Id and log
# approval challenges for webhook correlation.
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
Atomic Nebula Projects CLI

Usage: an-projects.sh [--env <workspace>] <command> [options]

Commands:
  list                         List projects
  types                        Get project type definitions
  custom-fields                Get project custom-fields schema
  create                       Create a project
  update <projectId>           Update a project
  archive <projectId>          Archive a project

Global Options:
  --env <env>                  Target workspace slug (e.g., spider, dev, circeaurasupport)

list Options:
  --status <value>
  --owner-id <userId>

create Options:
  --name <text>                Required
  --key <text>                 Required
  --description <text>
  --status <value>
  --start-date <date>
  --target-end-date <date>

update Options:
  --name <text>
  --description <text>
  --status <value>
  --owner-id <userId>
  --start-date <date>
  --target-end-date <date>
  --actual-end-date <date>

archive Options:
  --reason <text>

Examples:
  an-projects.sh list --status active
  an-projects.sh types
  an-projects.sh custom-fields
  an-projects.sh create --name "Content Backlog" --key "content-backlog"
  an-projects.sh update PROJECT-ID --status active --description "Current work backlog"
  an-projects.sh archive PROJECT-ID --reason "Completed"
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

build_list_url() {
  local url="${BASE_URL}/api/v1/atomicnebula/projects"
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
      --status) add_query_param "status" "$2"; shift 2 ;;
      --owner-id) add_query_param "ownerId" "$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  echo "$url"
}

command_list() {
  local url
  url=$(build_list_url "$@")
  request_json "GET" "$url"
  print_or_fail "list"
}

command_types() {
  request_json "GET" "${BASE_URL}/api/v1/atomicnebula/projects/types"
  print_or_fail "types"
}

command_custom_fields() {
  request_json "GET" "${BASE_URL}/api/v1/atomicnebula/projects/custom-fields/schema"
  print_or_fail "custom-fields"
}

command_create() {
  local name=""
  local key=""
  local description=""
  local status=""
  local start_date=""
  local target_end_date=""
  local payload='{}'

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --key) key="$2"; shift 2 ;;
      --description) description="$2"; shift 2 ;;
      --status) status="$2"; shift 2 ;;
      --start-date) start_date="$2"; shift 2 ;;
      --target-end-date) target_end_date="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$name" || -z "$key" ]]; then
    echo "Error: --name and --key are required" >&2
    exit 1
  fi

  payload=$(add_string_field "$payload" "name" "$name")
  payload=$(add_string_field "$payload" "key" "$key")
  payload=$(add_string_field "$payload" "description" "$description")
  payload=$(add_string_field "$payload" "status" "$status")
  payload=$(add_string_field "$payload" "startDate" "$start_date")
  payload=$(add_string_field "$payload" "targetEndDate" "$target_end_date")

  request_json "POST" "${BASE_URL}/api/v1/atomicnebula/projects" "$payload" "true"
  print_or_fail "create"
}

command_update() {
  local project_id="${1:-}"
  shift || true
  if [[ -z "$project_id" ]]; then
    echo "Error: projectId is required" >&2
    exit 1
  fi

  local name=""
  local description=""
  local status=""
  local owner_id=""
  local start_date=""
  local target_end_date=""
  local actual_end_date=""
  local payload='{}'

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --description) description="$2"; shift 2 ;;
      --status) status="$2"; shift 2 ;;
      --owner-id) owner_id="$2"; shift 2 ;;
      --start-date) start_date="$2"; shift 2 ;;
      --target-end-date) target_end_date="$2"; shift 2 ;;
      --actual-end-date) actual_end_date="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  payload=$(add_string_field "$payload" "name" "$name")
  payload=$(add_string_field "$payload" "description" "$description")
  payload=$(add_string_field "$payload" "status" "$status")
  payload=$(add_string_field "$payload" "ownerId" "$owner_id")
  payload=$(add_string_field "$payload" "startDate" "$start_date")
  payload=$(add_string_field "$payload" "targetEndDate" "$target_end_date")
  payload=$(add_string_field "$payload" "actualEndDate" "$actual_end_date")

  if [[ "$payload" == "{}" ]]; then
    echo "Error: no update fields provided" >&2
    exit 1
  fi

  request_json "PATCH" "${BASE_URL}/api/v1/atomicnebula/projects/${project_id}" "$payload" "true"
  print_or_fail "update"
}

command_archive() {
  local project_id="${1:-}"
  shift || true
  if [[ -z "$project_id" ]]; then
    echo "Error: projectId is required" >&2
    exit 1
  fi

  local reason=""
  local payload='{}'

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  payload=$(add_string_field "$payload" "reason" "$reason")
  request_json "POST" "${BASE_URL}/api/v1/atomicnebula/projects/${project_id}/archive" "$payload" "true"
  print_or_fail "archive"
}

case "${1:-}" in
  list)
    shift
    command_list "$@"
    ;;
  types)
    shift
    command_types "$@"
    ;;
  custom-fields)
    shift
    command_custom_fields "$@"
    ;;
  create)
    shift
    command_create "$@"
    ;;
  update)
    shift
    command_update "$@"
    ;;
  archive)
    shift
    command_archive "$@"
    ;;
  *)
    echo "Error: Unknown command '${1:-}'" >&2
    usage
    exit 1
    ;;
esac

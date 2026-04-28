#!/bin/bash
#
# Atomic Nebula Content CLI Helper
#
# Supports content item list/get/create/update, markdown body access,
# and CRM entity linking through the Atomic Nebula external REST API.
# Write calls send X-Run-Id and log approval challenges for webhook correlation.
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
ENV_PREFIX=$(print_env_prefix)

usage() {
  cat << 'USAGE'
Atomic Nebula Content CLI

Usage: an-content.sh [--env <workspace>] <command> [options]

Commands:
  list                            List content items
  get <contentId>                 Get one content item
  markdown <contentId>            Read markdown for a content item
  create                          Create a content item
  update <contentId>              Update content item metadata
  set-markdown <contentId>        Replace markdown for a document-backed content item
  link-entity <contentId>         Link a content item to a CRM entity

Global Options:
  --env <env>                     Target workspace slug (e.g., spider, dev, circeaurasupport)

list Options:
  --type <contentType>
  --status <status>
  --owner-id <userId>
  --stage-id <stageId>
  --search <term>
  --page <n>
  --page-size <n>
  --sort-by <field>
  --sort-order <asc|desc>

create Options:
  --title <text>                  Title (required)
  --description <text>
  --content-type <type>
  --owner-user-id <userId>
  --status <status>
  --tag <value>                   Repeatable
  --tags <csv>                    Comma-separated alternative to --tag
  --markdown <text>
  --markdown-file <path>
  --entity-type <type>
  --entity-id <id>
  --source-asset-id <id>          Repeatable
  --source-asset-ids <csv>        Comma-separated alternative

update Options:
  --title <text>
  --description <text>
  --owner-user-id <userId>
  --status <status>
  --tag <value>                   Repeatable
  --tags <csv>                    Comma-separated alternative

set-markdown Options:
  --file <path>                   Markdown file path
  --markdown <text>               Inline markdown text
  --expected-version <n>
  --conflict-strategy <mode>      overwrite|reject

link-entity Options:
  --entity-type <type>            contact|company|deal|lead
  --entity-id <id>
  --link-type <value>

Examples:
  an-content.sh list --type content_idea --page 1 --page-size 20
  an-content.sh get CONTENT-ID
  an-content.sh markdown CONTENT-ID
  an-content.sh create --title "March social idea" --content-type content_idea
  an-content.sh create --title "Launch memo" --markdown-file ./memo.md
  an-content.sh update CONTENT-ID --title "Updated title" --status archived --tag launch
  an-content.sh set-markdown CONTENT-ID --file ./updated.md --expected-version 3 --conflict-strategy reject
  an-content.sh link-entity CONTENT-ID --entity-type contact --entity-id CONTACT-ID
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

read_file_content() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo "Error: file not found: $file_path" >&2
    exit 1
  fi
  cat "$file_path"
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

build_list_url() {
  local url="${BASE_URL}/api/v1/atomicnebula/content/items"
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
      --type) add_query_param "type" "$2"; shift 2 ;;
      --status) add_query_param "status" "$2"; shift 2 ;;
      --owner-id) add_query_param "ownerId" "$2"; shift 2 ;;
      --stage-id) add_query_param "stageId" "$2"; shift 2 ;;
      --search) add_query_param "search" "$2"; shift 2 ;;
      --page) add_query_param "page" "$2"; shift 2 ;;
      --page-size) add_query_param "pageSize" "$2"; shift 2 ;;
      --sort-by) add_query_param "sortBy" "$2"; shift 2 ;;
      --sort-order) add_query_param "sortOrder" "$2"; shift 2 ;;
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

command_get() {
  local content_id="${1:-}"
  if [[ -z "$content_id" ]]; then
    echo "Error: contentId is required" >&2
    exit 1
  fi
  request_json "GET" "${BASE_URL}/api/v1/atomicnebula/content/items/${content_id}"
  print_or_fail "get"
}

command_markdown() {
  local content_id="${1:-}"
  if [[ -z "$content_id" ]]; then
    echo "Error: contentId is required" >&2
    exit 1
  fi
  request_json "GET" "${BASE_URL}/api/v1/atomicnebula/content/items/${content_id}/markdown"
  print_or_fail "markdown"
}

command_create() {
  local title=""
  local description=""
  local content_type=""
  local owner_user_id=""
  local status=""
  local markdown_text=""
  local markdown_file=""
  local entity_type=""
  local entity_id=""
  local source_asset_ids_csv=""
  local payload='{}'

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --description) description="$2"; shift 2 ;;
      --content-type) content_type="$2"; shift 2 ;;
      --owner-user-id) owner_user_id="$2"; shift 2 ;;
      --status) status="$2"; shift 2 ;;
      --tag) payload=$(append_array_value "$payload" "tags" "$2"); shift 2 ;;
      --tags) payload=$(merge_csv_into_array "$payload" "tags" "$2"); shift 2 ;;
      --markdown) markdown_text="$2"; shift 2 ;;
      --markdown-file) markdown_file="$2"; shift 2 ;;
      --entity-type) entity_type="$2"; shift 2 ;;
      --entity-id) entity_id="$2"; shift 2 ;;
      --source-asset-id) payload=$(append_array_value "$payload" "sourceAssetIds" "$2"); shift 2 ;;
      --source-asset-ids) source_asset_ids_csv="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$title" ]]; then
    echo "Error: --title is required" >&2
    exit 1
  fi
  if [[ -n "$markdown_text" && -n "$markdown_file" ]]; then
    echo "Error: use only one of --markdown or --markdown-file" >&2
    exit 1
  fi
  if [[ -n "$entity_type" && -z "$entity_id" ]]; then
    echo "Error: --entity-id is required when --entity-type is provided" >&2
    exit 1
  fi
  if [[ -n "$entity_id" && -z "$entity_type" ]]; then
    echo "Error: --entity-type is required when --entity-id is provided" >&2
    exit 1
  fi
  if [[ -n "$markdown_file" ]]; then
    markdown_text=$(read_file_content "$markdown_file")
  fi

  payload=$(add_string_field "$payload" "title" "$title")
  payload=$(add_string_field "$payload" "description" "$description")
  payload=$(add_string_field "$payload" "contentType" "$content_type")
  payload=$(add_string_field "$payload" "ownerUserId" "$owner_user_id")
  payload=$(add_string_field "$payload" "status" "$status")
  payload=$(add_string_field "$payload" "markdown" "$markdown_text")
  payload=$(add_string_field "$payload" "entityType" "$entity_type")
  payload=$(add_string_field "$payload" "entityId" "$entity_id")
  payload=$(merge_csv_into_array "$payload" "sourceAssetIds" "$source_asset_ids_csv")

  request_json "POST" "${BASE_URL}/api/v1/atomicnebula/content/items" "$payload" "true"
  print_or_fail "create"
}

command_update() {
  local content_id="${1:-}"
  shift || true
  if [[ -z "$content_id" ]]; then
    echo "Error: contentId is required" >&2
    exit 1
  fi

  local title=""
  local description=""
  local owner_user_id=""
  local status=""
  local payload='{}'

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --description) description="$2"; shift 2 ;;
      --owner-user-id) owner_user_id="$2"; shift 2 ;;
      --status) status="$2"; shift 2 ;;
      --tag) payload=$(append_array_value "$payload" "tags" "$2"); shift 2 ;;
      --tags) payload=$(merge_csv_into_array "$payload" "tags" "$2"); shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  payload=$(add_string_field "$payload" "title" "$title")
  payload=$(add_string_field "$payload" "description" "$description")
  payload=$(add_string_field "$payload" "ownerUserId" "$owner_user_id")
  payload=$(add_string_field "$payload" "status" "$status")

  if [[ "$payload" == "{}" ]]; then
    echo "Error: no update fields provided" >&2
    exit 1
  fi

  request_json "PATCH" "${BASE_URL}/api/v1/atomicnebula/content/items/${content_id}" "$payload" "true"
  print_or_fail "update"
}

command_set_markdown() {
  local content_id="${1:-}"
  shift || true
  if [[ -z "$content_id" ]]; then
    echo "Error: contentId is required" >&2
    exit 1
  fi

  local file_path=""
  local markdown_text=""
  local expected_version=""
  local conflict_strategy=""
  local payload='{}'

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) file_path="$2"; shift 2 ;;
      --markdown) markdown_text="$2"; shift 2 ;;
      --expected-version) expected_version="$2"; shift 2 ;;
      --conflict-strategy) conflict_strategy="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -n "$file_path" && -n "$markdown_text" ]]; then
    echo "Error: use only one of --file or --markdown" >&2
    exit 1
  fi
  if [[ -z "$file_path" && -z "$markdown_text" ]]; then
    echo "Error: one of --file or --markdown is required" >&2
    exit 1
  fi
  if [[ -n "$file_path" ]]; then
    markdown_text=$(read_file_content "$file_path")
  fi

  payload=$(add_string_field "$payload" "markdown" "$markdown_text")
  payload=$(add_number_field "$payload" "expectedVersion" "$expected_version")
  payload=$(add_string_field "$payload" "conflictStrategy" "$conflict_strategy")

  request_json "PUT" "${BASE_URL}/api/v1/atomicnebula/content/items/${content_id}/markdown" "$payload" "true"
  print_or_fail "set-markdown"
}

command_link_entity() {
  local content_id="${1:-}"
  shift || true
  if [[ -z "$content_id" ]]; then
    echo "Error: contentId is required" >&2
    exit 1
  fi

  local entity_type=""
  local entity_id=""
  local link_type=""
  local payload='{}'

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --entity-type) entity_type="$2"; shift 2 ;;
      --entity-id) entity_id="$2"; shift 2 ;;
      --link-type) link_type="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$entity_type" || -z "$entity_id" ]]; then
    echo "Error: --entity-type and --entity-id are required" >&2
    exit 1
  fi

  payload=$(add_string_field "$payload" "entityType" "$entity_type")
  payload=$(add_string_field "$payload" "entityId" "$entity_id")
  payload=$(add_string_field "$payload" "linkType" "$link_type")

  request_json "POST" "${BASE_URL}/api/v1/atomicnebula/content/items/${content_id}/entity-links" "$payload" "true"
  print_or_fail "link-entity"
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
  markdown)
    shift
    command_markdown "$@"
    ;;
  create)
    shift
    command_create "$@"
    ;;
  update)
    shift
    command_update "$@"
    ;;
  set-markdown)
    shift
    command_set_markdown "$@"
    ;;
  link-entity)
    shift
    command_link_entity "$@"
    ;;
  *)
    echo "Error: Unknown command '${1:-}'" >&2
    usage
    exit 1
    ;;
esac

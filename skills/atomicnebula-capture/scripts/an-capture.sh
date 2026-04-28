#!/bin/bash
#
# Atomic Nebula Context Capture CLI Helper
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
Atomic Nebula Capture CLI

Usage: an-capture.sh [--env <workspace>] <command> [options]

Commands:
  create                  Create a durable context capture
  list                    List context captures
  get <captureId>         Get one context capture

create Options:
  --type <type>           thought|decision|session_summary|correction|preference|implementation_note
  --text <text>           Inline capture content
  --file <path>           Read capture content from file
  --summary <text>        Optional short summary
  --importance <n>        Optional 0-10 importance score
  --source-agent <value>  Optional source agent name
  --source-tool <value>   Optional source skill/tool name
  --source-thread <value> Optional source conversation/thread ID
  --entity-type <type>    Repeatable entity link type
  --entity-id <id>        Repeatable entity link ID, paired by order with --entity-type
  --metadata <json>       Optional JSON object metadata

list Options:
  --type <type>
  --entity-type <type>
  --entity-id <id>
  --source-agent <value>
  --search <term>
  --limit <n>

Examples:
  an-capture.sh create --type decision --text "Use context captures for assistant memory."
  an-capture.sh create --type session_summary --file ./summary.md
  an-capture.sh create --type preference --text "Use concise status updates." --entity-type contact --entity-id CONTACT-ID
  an-capture.sh list --type decision --limit 20
  an-capture.sh get CAPTURE-ID
USAGE
}

require_api_key() {
  if [[ -z "${API_KEY:-}" ]]; then
    echo "Error: No API key found for workspace '${AN_ENV}'." >&2
    echo "Set ATOMICNEBULA_API_KEY or configure ${AN_ASSISTANT_CONFIG_FILE}." >&2
    exit 1
  fi
}

url_encode() {
  jq -rn --arg value "$1" '$value | @uri'
}

api_json() {
  local method="$1"
  local url="$2"
  local body="${3:-}"
  local response
  local curl_status

  set +e
  if [[ -n "$body" ]]; then
    response=$(curl "${CURL_BASE[@]}" -S -w $'\n%{http_code}' -X "$method" --data "$body" "$url")
    curl_status=$?
  else
    response=$(curl "${CURL_BASE[@]}" -S -w $'\n%{http_code}' -X "$method" "$url")
    curl_status=$?
  fi
  set -e

  if [[ $curl_status -ne 0 ]]; then
    echo "Error: request failed before receiving an API response" >&2
    return "$curl_status"
  fi

  local http_status="${response##*$'\n'}"
  local response_body="${response%$'\n'*}"

  if [[ "$http_status" -lt 200 || "$http_status" -ge 300 ]]; then
    echo "$response_body" | jq . >&2 || echo "$response_body" >&2
    return 1
  fi

  if echo "$response_body" | jq -e 'type == "object" and has("success") and .success == false' >/dev/null; then
    echo "$response_body" | jq . >&2
    return 1
  fi

  echo "$response_body" | jq .
}

create_capture() {
  local capture_type=""
  local text=""
  local file=""
  local summary=""
  local importance=""
  local source_agent=""
  local source_tool=""
  local source_thread=""
  local metadata="{}"
  local entity_types=()
  local entity_ids=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) capture_type="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      --file) file="$2"; shift 2 ;;
      --summary) summary="$2"; shift 2 ;;
      --importance) importance="$2"; shift 2 ;;
      --source-agent) source_agent="$2"; shift 2 ;;
      --source-tool) source_tool="$2"; shift 2 ;;
      --source-thread) source_thread="$2"; shift 2 ;;
      --entity-type) entity_types+=("$2"); shift 2 ;;
      --entity-id) entity_ids+=("$2"); shift 2 ;;
      --metadata) metadata="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -n "$file" ]]; then
    if [[ ! -f "$file" ]]; then
      echo "Error: file not found: $file" >&2
      exit 1
    fi
    text="$(cat "$file")"
  fi
  if [[ -z "$text" ]]; then
    echo "Error: create requires --text or --file" >&2
    exit 1
  fi
  if [[ ${#entity_types[@]} -ne ${#entity_ids[@]} ]]; then
    echo "Error: --entity-type and --entity-id must be provided in pairs" >&2
    exit 1
  fi
  if ! echo "$metadata" | jq -e 'type == "object"' >/dev/null; then
    echo "Error: --metadata must be a JSON object" >&2
    exit 1
  fi
  if [[ -n "$importance" ]] && ! [[ "$importance" =~ ^([0-9]+)(\.[0-9]+)?$ ]]; then
    echo "Error: --importance must be a number between 0 and 10" >&2
    exit 1
  fi
  if [[ -n "$importance" ]] && ! awk -v value="$importance" 'BEGIN { exit !(value >= 0 && value <= 10) }'; then
    echo "Error: --importance must be a number between 0 and 10" >&2
    exit 1
  fi

  local links="[]"
  local i=0
  while [[ $i -lt ${#entity_types[@]} ]]; do
    links=$(echo "$links" | jq \
      --arg entityType "${entity_types[$i]}" \
      --arg entityId "${entity_ids[$i]}" \
      '. + [{entityType: $entityType, entityId: $entityId}]')
    i=$((i + 1))
  done

  local body
  body=$(jq -n \
    --arg content "$text" \
    --arg captureType "$capture_type" \
    --arg summary "$summary" \
    --arg importance "$importance" \
    --arg sourceAgent "$source_agent" \
    --arg sourceTool "$source_tool" \
    --arg sourceThreadId "$source_thread" \
    --argjson metadata "$metadata" \
    --argjson links "$links" \
    '{
      content: $content,
      captureType: (if $captureType == "" then null else $captureType end),
      summary: (if $summary == "" then null else $summary end),
      importance: (if $importance == "" then null else ($importance | tonumber) end),
      sourceAgent: (if $sourceAgent == "" then null else $sourceAgent end),
      sourceTool: (if $sourceTool == "" then null else $sourceTool end),
      sourceThreadId: (if $sourceThreadId == "" then null else $sourceThreadId end),
      metadata: $metadata,
      links: $links
    } | with_entries(select(.value != null))')

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Creating context capture in ${BASE_URL}" >&2
  api_json POST "${BASE_URL}/api/v1/atomicnebula/context/captures" "$body"
}

list_captures() {
  local params=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) params+=("captureType=$(url_encode "$2")"); shift 2 ;;
      --entity-type) params+=("entityType=$(url_encode "$2")"); shift 2 ;;
      --entity-id) params+=("entityId=$(url_encode "$2")"); shift 2 ;;
      --source-agent) params+=("sourceAgent=$(url_encode "$2")"); shift 2 ;;
      --search) params+=("search=$(url_encode "$2")"); shift 2 ;;
      --limit) params+=("limit=$(url_encode "$2")"); shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  local query=""
  if [[ ${#params[@]} -gt 0 ]]; then
    query=$(printf '%s\n' "${params[@]}" | paste -sd'&' -)
    query="?${query}"
  fi

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Listing context captures from ${BASE_URL}" >&2
  api_json GET "${BASE_URL}/api/v1/atomicnebula/context/captures${query}"
}

get_capture() {
  local capture_id="${1:-}"
  if [[ -z "$capture_id" ]]; then
    echo "Error: capture ID is required" >&2
    exit 1
  fi

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Getting context capture from ${BASE_URL}" >&2
  api_json GET "${BASE_URL}/api/v1/atomicnebula/context/captures/${capture_id}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" || -z "${1:-}" ]]; then
  usage
  exit 0
fi

require_api_key

case "${1:-}" in
  create) shift; create_capture "$@" ;;
  list) shift; list_captures "$@" ;;
  get) shift; get_capture "$@" ;;
  *) echo "Error: unknown command '$1'" >&2; usage; exit 1 ;;
esac

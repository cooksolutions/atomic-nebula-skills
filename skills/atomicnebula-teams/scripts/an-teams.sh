#!/bin/bash
#
# Atomic Nebula Teams CLI Helper
#
# Lists user-scoped Teams chats/messages and queues replies through the
# Atomic Nebula assistant REST API. Write calls send X-Run-Id and log
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
ENV_PREFIX=$(print_env_prefix)

usage() {
  cat << 'USAGE'
Atomic Nebula Teams CLI

Usage: an-teams.sh [--env <workspace>] <command> [options]

Commands:
  status                           Show Teams channel availability for the current user
  chats                            List accessible Teams chats
  get <chatId>                     Get one Teams chat
  messages <chatId>                List messages in a Teams chat
  reply <chatId>                   Reply in an existing Teams chat/thread

Global Options:
  --env <env>                      Target workspace slug (e.g., spider, dev, circeaurasupport)

chats Options:
  --chat-type <type>               oneOnOne | group | meeting | channel
  --credential-id <id>             Filter to a specific Teams credential
  --limit <n>                      Max results (default: 50)
  --cursor <cursor>                Pagination cursor

messages Options:
  --limit <n>                      Max results (default: 50)
  --cursor <cursor>                Pagination cursor

reply Options:
  --body <text>                    Reply text (required)
  --reply-to <messageId>           Required for channel replies
  --body-content-type <type>       text | html (default: text)
  --importance <value>             normal | high | urgent

Examples:
  an-teams.sh status
  an-teams.sh chats --chat-type meeting --limit 20
  an-teams.sh get TC-123
  an-teams.sh messages TC-123 --limit 25
  an-teams.sh reply TC-123 --body "I can do 3pm."
  an-teams.sh reply TC-456 --reply-to TM-789 --body "Looks good to me."
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
  printf '{"timestamp":"%s","runId":"%s","challengeId":"%s","action":"%s","workspace":"%s","pid":%d,"ppid":%d}\n' \
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
  local path="$2"
  local body="${3:-}"
  local include_run_id="${4:-false}"
  local -a headers=("${CURL_BASE[@]}")

  if [[ "$include_run_id" == "true" ]]; then
    headers+=(-H "X-Run-Id: $RUN_ID")
  fi

  local response
  if [[ -n "$body" ]]; then
    response=$(curl "${headers[@]}" -w "\n%{http_code}" -X "$method" -d "$body" "${BASE_URL}${path}")
  else
    response=$(curl "${headers[@]}" -w "\n%{http_code}" -X "$method" "${BASE_URL}${path}")
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

status() {
  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Getting Teams channel status from ${BASE_URL}" >&2
  request_json GET "/api/v1/atomicnebula/channels"
  if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
  fi
  echo "$BODY" | jq '{
    success: .success,
    teams: ([((.data.channels // [])[] | select(.type == "teams"))][0] // null)
  }'
}

list_chats() {
  local chat_type="" credential_id="" limit="50" cursor=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --chat-type) chat_type="$2"; shift 2 ;;
      --credential-id) credential_id="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      --cursor) cursor="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  local query="?limit=$(uri "$limit")"
  if [[ -n "$chat_type" ]]; then
    query+="&chatType=$(uri "$chat_type")"
  fi
  if [[ -n "$credential_id" ]]; then
    query+="&credentialId=$(uri "$credential_id")"
  fi
  if [[ -n "$cursor" ]]; then
    query+="&cursor=$(uri "$cursor")"
  fi

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Listing Teams chats from ${BASE_URL}" >&2
  request_json GET "/api/v1/atomicnebula/teams/chats${query}"
  if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
  fi
  echo "$BODY" | jq '{
    success: .success,
    pageStatus: .data.pageStatus,
    isDone: .data.isDone,
    continueCursor: .data.continueCursor,
    count: (.data.page | length),
    chats: [(.data.page // [])[] | {
      chatId: .chatId,
      chatType: .chatType,
      displayName: (.displayName // .topic // .channelName // "(No title)"),
      teamName: .teamName,
      channelName: .channelName,
      unreadCount: .unreadCount,
      lastMessageAt: .lastMessageAt,
      lastMessagePreview: .lastMessagePreview
    }]
  }'
}

get_chat() {
  local chat_id="${1:-}"
  if [[ -z "$chat_id" ]]; then
    echo "Error: chatId is required" >&2
    exit 1
  fi

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Getting Teams chat ${chat_id} from ${BASE_URL}" >&2
  curl "${CURL_BASE[@]}" "${BASE_URL}/api/v1/atomicnebula/teams/chats/$(uri "$chat_id")" | jq .
}

list_messages() {
  local chat_id="${1:-}"
  shift || true
  local limit="50" cursor=""

  if [[ -z "$chat_id" ]]; then
    echo "Error: chatId is required" >&2
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      --cursor) cursor="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  local query="?limit=$(uri "$limit")"
  if [[ -n "$cursor" ]]; then
    query+="&cursor=$(uri "$cursor")"
  fi

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Listing Teams messages for ${chat_id} from ${BASE_URL}" >&2
  request_json GET "/api/v1/atomicnebula/teams/chats/$(uri "$chat_id")/messages${query}"
  if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
  fi
  echo "$BODY" | jq '{
    success: .success,
    chat: (.data.chat | {
      chatId: .chatId,
      chatType: .chatType,
      displayName: (.displayName // .topic // .channelName // "(No title)")
    }),
    isDone: .data.isDone,
    continueCursor: .data.continueCursor,
    count: (.data.page | length),
    messages: [(.data.page // [])[] | {
      messageId: .messageId,
      direction: .direction,
      from: (.fromDisplayName // .fromEmail // .fromUserId),
      bodyPreview: .bodyPreview,
      importance: .importance,
      status: .status,
      createdAt: .createdAt,
      replyToMessageId: .replyToMessageId
    }]
  }'
}

reply() {
  local chat_id="${1:-}"
  shift || true
  local body="" reply_to="" body_content_type="" importance=""

  if [[ -z "$chat_id" ]]; then
    echo "Error: chatId is required" >&2
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body) body="$2"; shift 2 ;;
      --reply-to|--reply-to-message-id) reply_to="$2"; shift 2 ;;
      --body-content-type) body_content_type="$2"; shift 2 ;;
      --html) body_content_type="html"; shift ;;
      --importance) importance="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$body" ]]; then
    echo "Error: --body is required" >&2
    exit 1
  fi

  local payload
  payload=$(jq -n \
    --arg body "$body" \
    --arg replyToMessageId "$reply_to" \
    --arg bodyContentType "$body_content_type" \
    --arg importance "$importance" \
    '{
      body: $body
    }
    + (if ($replyToMessageId | length) > 0 then {replyToMessageId: $replyToMessageId} else {} end)
    + (if ($bodyContentType | length) > 0 then {bodyContentType: $bodyContentType} else {} end)
    + (if ($importance | length) > 0 then {importance: $importance} else {} end)')

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Replying in Teams chat ${chat_id} via ${BASE_URL}" >&2
  request_json POST "/api/v1/atomicnebula/teams/chats/$(uri "$chat_id")/messages" "$payload" "true"
  print_or_fail "teams.reply"
}

case "${1:-}" in
  status)
    shift
    status "$@"
    ;;
  chats)
    shift
    list_chats "$@"
    ;;
  get)
    shift
    get_chat "$@"
    ;;
  messages)
    shift
    list_messages "$@"
    ;;
  reply)
    shift
    reply "$@"
    ;;
  *)
    echo "Error: Unknown command '${1:-}'" >&2
    usage >&2
    exit 1
    ;;
esac

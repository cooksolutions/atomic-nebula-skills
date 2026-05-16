#!/bin/bash
#
# Atomic Nebula Social CLI Helper
#
# Drives social posting operations through the assistant REST API.
# Supports listing accounts/posts/assets and (when the public routes
# ship) drafting, scheduling, cancelling, and generating media.
#
# Until the external HTTP routes are built, read commands work against
# any deployed instance; write commands print a helpful "endpoints
# pending" message rather than failing silently.
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
CURL_BASE=(-s -H "Authorization: Bearer ${API_KEY:-}" -H "Content-Type: application/json")

usage() {
  cat << 'USAGE'
Atomic Nebula Social CLI

Usage: an-social.sh [--env <workspace>] <command> [options]

Commands (read — currently functional when REST routes are deployed):
  accounts                              List connected social accounts
  account <accountId>                   Get a single account
  posts                                 List social posts (filters below)
  post <postId>                         Get a single post
  platform-spec <platform>              Get per-platform constraints
  platform-specs                        List supported platforms
  swipe-file                            Search the swipe-file library
  templates                             List post templates
  snippets                              List caption snippets
  assets                                List workspace social assets

Commands (write — registered, awaiting Azure REST routes):
  draft-create                          Create a post draft
  draft-update <postId>                 Update a post draft
  schedule <postId>                     Schedule a draft
  cancel <postId>                       Cancel a scheduled post
  generate-media                        Generate image/video via AI

Global Options:
  --env <env>                           Target workspace slug

accounts Options:
  --platform <facebook|instagram|linkedin>
  --active-only

posts Options:
  --status <draft|scheduled|publishing|published|failed|cancelled>
  --platform <facebook|instagram|linkedin>
  --account-id <id>
  --search <text>
  --limit <n>

swipe-file Options:
  --query <text>
  --content-type <type>
  --category <category>
  --tag <tag>
  --limit <n>

templates Options:
  --category <category>
  --platform <facebook|instagram|linkedin>
  --search <text>
  --limit <n>

snippets Options:
  --category <category>
  --search <text>
  --limit <n>

assets Options:
  --type <image|video|document|logo|color|font>
  --category <category>
  --tag <tag>
  --search <text>
  --limit <n>

draft-create Options:
  --text <text>                         Required. Post body
  --account-id <id>                     Repeatable. Required (max 6)
  --link <url>
  --tag <value>                         Repeatable
  --template-id <id>
  --account-caption <accountId>=<text>  Repeatable. Per-account caption variant
  --source-draft-id <id>

draft-update Options:
  --text <text>
  --link <url|null>                     Pass "null" to clear
  --account-id <id>                     Repeatable. Replaces all account ids
  --tag <value>                         Repeatable
  --account-caption <accountId>=<text>  Repeatable

schedule Options:
  --at <iso8601 | unix-ms>              Required. Future timestamp

generate-media Options:
  --type <image|video>                  Required (only "image" currently configured)
  --prompt <text>                       Required
  --size <1024x1024|1024x1792|1792x1024>
  --count <n>                           Default 1, max 4
  --attach-to <postId>

Examples:
  an-social.sh accounts --platform linkedin
  an-social.sh posts --status draft --limit 5
  an-social.sh draft-create --text "Hello world" --account-id LI-123 --account-id IG-456 --tag launch
  an-social.sh schedule POST-ID --at 2026-06-01T09:00:00Z
  an-social.sh generate-media --type image --prompt "turquoise wave"

Notes:
  * Read commands require deployed external REST routes (see SKILL.md).
  * Write commands are registered in the assistant operation catalog and
    will work as soon as the matching Azure Functions handlers ship.
  * Until then, the recommended path is the Luna web chat in the AN app.
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

endpoints_pending() {
  local key="$1"
  echo "Operation '$key' is registered in the assistant catalog but the public REST endpoint hasn't shipped yet."
  echo "See skills/atomicnebula-social/SKILL.md → 'Adding Public REST Routes' for the build path."
  echo "Workaround: use Luna in the AN web app (/assistant) which calls the same Convex internals directly."
  exit 2
}

# Strip --env <value> from the argument list so subcommands see only their own flags.
ARGS=()
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--env" ]]; then
    prev=""
    continue
  fi
  if [[ "$arg" == "--env" ]]; then
    prev="--env"
    continue
  fi
  ARGS+=("$arg")
done
set -- "${ARGS[@]:-}"

CMD="${1:-}"
shift || true

build_query() {
  local pairs=("$@")
  if [[ ${#pairs[@]} -eq 0 ]]; then
    echo ""
    return
  fi
  local joined
  joined=$(IFS='&'; echo "${pairs[*]}")
  echo "?${joined}"
}

case "$CMD" in
  accounts)
    QPARAMS=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --platform) QPARAMS+=("platform=$2"); shift 2;;
        --active-only) QPARAMS+=("isActive=true"); shift;;
        *) echo "Unknown flag: $1" >&2; exit 1;;
      esac
    done
    request_json GET "${BASE_URL}/api/v1/atomicnebula/social/accounts$(build_query "${QPARAMS[@]:-}")"
    print_or_fail "social.accounts.list"
    ;;

  account)
    ID="${1:-}"
    if [[ -z "$ID" ]]; then echo "Usage: an-social.sh account <accountId>" >&2; exit 1; fi
    request_json GET "${BASE_URL}/api/v1/atomicnebula/social/accounts/${ID}"
    print_or_fail "social.accounts.get"
    ;;

  posts)
    QPARAMS=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --status) QPARAMS+=("publishStatus=$2"); shift 2;;
        --platform) QPARAMS+=("platform=$2"); shift 2;;
        --account-id) QPARAMS+=("accountId=$2"); shift 2;;
        --search) QPARAMS+=("search=$2"); shift 2;;
        --limit) QPARAMS+=("limit=$2"); shift 2;;
        *) echo "Unknown flag: $1" >&2; exit 1;;
      esac
    done
    request_json GET "${BASE_URL}/api/v1/atomicnebula/social/posts$(build_query "${QPARAMS[@]:-}")"
    print_or_fail "social.posts.list"
    ;;

  post)
    ID="${1:-}"
    if [[ -z "$ID" ]]; then echo "Usage: an-social.sh post <postId>" >&2; exit 1; fi
    request_json GET "${BASE_URL}/api/v1/atomicnebula/social/posts/${ID}"
    print_or_fail "social.posts.get"
    ;;

  platform-spec)
    PLAT="${1:-}"
    if [[ -z "$PLAT" ]]; then echo "Usage: an-social.sh platform-spec <platform>" >&2; exit 1; fi
    request_json GET "${BASE_URL}/api/v1/atomicnebula/social/platform-specs/${PLAT}"
    print_or_fail "social.platform_specs.get"
    ;;

  platform-specs)
    request_json GET "${BASE_URL}/api/v1/atomicnebula/social/platform-specs"
    print_or_fail "social.platform_specs.list"
    ;;

  swipe-file)
    QPARAMS=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --query) QPARAMS+=("search=$2"); shift 2;;
        --content-type) QPARAMS+=("contentType=$2"); shift 2;;
        --category) QPARAMS+=("category=$2"); shift 2;;
        --tag) QPARAMS+=("tag=$2"); shift 2;;
        --limit) QPARAMS+=("limit=$2"); shift 2;;
        *) echo "Unknown flag: $1" >&2; exit 1;;
      esac
    done
    request_json GET "${BASE_URL}/api/v1/atomicnebula/social/swipe-file$(build_query "${QPARAMS[@]:-}")"
    print_or_fail "social.swipe_file.list"
    ;;

  templates)
    QPARAMS=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --category) QPARAMS+=("category=$2"); shift 2;;
        --platform) QPARAMS+=("targetPlatform=$2"); shift 2;;
        --search) QPARAMS+=("search=$2"); shift 2;;
        --limit) QPARAMS+=("limit=$2"); shift 2;;
        *) echo "Unknown flag: $1" >&2; exit 1;;
      esac
    done
    request_json GET "${BASE_URL}/api/v1/atomicnebula/social/templates$(build_query "${QPARAMS[@]:-}")"
    print_or_fail "social.templates.list"
    ;;

  snippets)
    QPARAMS=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --category) QPARAMS+=("category=$2"); shift 2;;
        --search) QPARAMS+=("search=$2"); shift 2;;
        --limit) QPARAMS+=("limit=$2"); shift 2;;
        *) echo "Unknown flag: $1" >&2; exit 1;;
      esac
    done
    request_json GET "${BASE_URL}/api/v1/atomicnebula/social/snippets$(build_query "${QPARAMS[@]:-}")"
    print_or_fail "social.snippets.list"
    ;;

  assets)
    QPARAMS=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type) QPARAMS+=("assetType=$2"); shift 2;;
        --category) QPARAMS+=("category=$2"); shift 2;;
        --tag) QPARAMS+=("tag=$2"); shift 2;;
        --search) QPARAMS+=("search=$2"); shift 2;;
        --limit) QPARAMS+=("limit=$2"); shift 2;;
        *) echo "Unknown flag: $1" >&2; exit 1;;
      esac
    done
    request_json GET "${BASE_URL}/api/v1/atomicnebula/social/assets$(build_query "${QPARAMS[@]:-}")"
    print_or_fail "social.assets.list"
    ;;

  draft-create|draft-update|schedule|cancel|generate-media)
    endpoints_pending "$CMD"
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    usage
    exit 1
    ;;
esac

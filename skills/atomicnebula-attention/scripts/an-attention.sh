#!/bin/bash
#
# Atomic Nebula Attention Hub CLI Helper
#
# A convenience script for querying the Atomic Nebula attention/focus queue.
# Supports multi-workspace targeting via --env flag.
#

set -euo pipefail

# Source shared env resolver
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

# Extract --env flag before any other arg parsing
eval "$(extract_env_flag "$@")"

# Resolve workspace (sets BASE_URL, API_KEY, AN_ENV)
resolve_an_env "$ENV_ARG"

# Handle help early before requiring API key
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "help" ]]; then
  cat << 'USAGE'
Atomic Nebula Attention Hub CLI

Usage: an-attention.sh [--env <workspace>] <command> [options]

Commands:
  summary            Get focus queue summary (counts + top priorities)
  focus              Get full focus queue with optional filters

Global Options:
  --env <env>        Target workspace slug (e.g., spider, dev, circeaurasupport)

Summary Options:
  --energy <value>   Current energy level (low, medium, high)

Focus Options:
  --energy <value>   Current energy level (low, medium, high)
  --bucket <value>   Filter by bucket (now, next, later)
  --include-snoozed  Include snoozed items
  --max-items <n>    Max results (default: 50, max: 250)
  --channel <value>  Filter by channel (email, sms, etc.)
  --status <value>   Filter by status
  --priority <value> Filter by priority
  --needs-response   Filter items needing response
  --search <term>    Search in title/preview

Workspace Config:
  API keys resolve from env vars, assistant-workspaces.json, or legacy OpenClaw config.
  Fallback env vars:
    ATOMICNEBULA_API_KEY / ATOMICNEBULA_BASE_URL (production)
    ATOMICNEBULA_DEV_API_KEY / ATOMICNEBULA_DEV_BASE_URL (dev)

Examples:
  # Quick summary of priorities
  an-attention.sh summary

  # Summary for low energy mode on dev workspace
  an-attention.sh --env dev summary --energy low

  # Show "now" bucket items
  an-attention.sh focus --bucket now

  # Items needing response
  an-attention.sh focus --needs-response

  # Email threads needing response
  an-attention.sh focus --channel email --needs-response

  # Search for specific items
  an-attention.sh focus --search "invoice"

  # High energy + now bucket
  an-attention.sh focus --bucket now --energy high

Scoring Algorithm:
  The focus queue uses a 7-factor scoring system:
  - Pinned (+50): User explicitly pinned the thread
  - Sprint (+25): Thread is in active sprint
  - SLA (0-45): Time-sensitive response needed
  - Priority (5-35): Thread priority level
  - Importance (0-30): Per-user importance setting
  - Energy (-3 to +12): Match with current energy
  - Staleness (0-10): How long since last review

  Buckets:
  - Now (score >= 80): Action immediately
  - Next (score >= 55): Plan for today
  - Later (score < 55): Backlog
USAGE
  exit 0
fi

if [[ -z "$API_KEY" ]]; then
  echo "Error: No API key found for workspace '${AN_ENV}'. Check assistant workspace config or run skills/shared/an-env-list.sh" >&2
  exit 1
fi

# Check for required tools
if ! command -v curl &> /dev/null; then
  echo "Error: curl is required" >&2
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "Error: jq is required" >&2
  exit 1
fi

# Common curl options
CURL_OPTS=(-s -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json")

# Show active workspace for non-default
ENV_PREFIX=$(print_env_prefix)

build_query_string() {
  local query=""
  local first=1

  add_param() {
    local key="$1"
    local value="$2"
    if [[ -n "$value" ]]; then
      if [[ $first -eq 1 ]]; then
        query="?${key}=$(printf '%s' "$value" | jq -sRr @uri)"
        first=0
      else
        query+="&${key}=$(printf '%s' "$value" | jq -sRr @uri)"
      fi
    fi
  }

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --energy) add_param "energy" "$2"; shift 2 ;;
      --bucket) add_param "bucket" "$2"; shift 2 ;;
      --include-snoozed) add_param "includeSnoozed" "true"; shift ;;
      --max-items) add_param "maxItems" "$2"; shift 2 ;;
      --channel) add_param "channel" "$2"; shift 2 ;;
      --status) add_param "status" "$2"; shift 2 ;;
      --priority) add_param "priority" "$2"; shift 2 ;;
      --needs-response) add_param "needsResponse" "true"; shift ;;
      --search) add_param "search" "$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  echo "$query"
}

get_summary() {
  local query
  query=$(build_query_string "$@")

  echo "${ENV_PREFIX}📊 Focus Queue Summary"
  echo ""

  curl "${CURL_OPTS[@]}" "${BASE_URL}/api/v1/atomicnebula/attention/summary${query}" | jq '{
    sprint: .data.sprint.name // "No active sprint",
    counts: .data.counts,
    topPriority: .data.topPriority
  }'
}

get_focus() {
  local query
  query=$(build_query_string "$@")

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Getting focus queue from ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" "${BASE_URL}/api/v1/atomicnebula/attention/focus${query}" | jq '{
    scoreVersion: .data.scoreVersion,
    sprint: .data.sprint.name // "No active sprint",
    totalCount: .data.totalCount,
    items: [.data.items[] | {
      bucket: .bucket,
      score: .score,
      threadId: .threadId,
      title: .title,
      channel: .channel,
      priority: .priority,
      needsResponse: .needsResponse,
      isPinned: .isPinned,
      inActiveSprint: .inActiveSprint,
      scoreBreakdown: .scoreBreakdown
    }] | sort_by(-.score)
  }'
}

# Main command parser
case "${1:-}" in
  summary)
    shift
    get_summary "$@"
    ;;
  focus)
    shift
    get_focus "$@"
    ;;
  "")
    echo "Error: No command specified" >&2
    exit 1
    ;;
  *)
    echo "Error: Unknown command '$1'" >&2
    exit 1
    ;;
esac

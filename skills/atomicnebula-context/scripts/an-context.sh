#!/bin/bash
#
# Atomic Nebula Context Graph CLI Helper
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
Atomic Nebula Context Graph CLI

Usage: an-context.sh [--env <workspace>] <command> [options]

Commands:
  person <contactId>       Get graph-backed person context
  thread <threadId>        Get graph-backed thread context
  deal <dealId>            Get graph-backed deal context
  project <projectId>      Get graph-backed project context
  bridge                   Find a bounded bridge between two graph nodes

Bridge Options:
  --from-type <type>
  --from-id <id>
  --to-type <type>
  --to-id <id>
  --max-hops <n>           Optional, defaulted by API
USAGE
}

require_api_key() {
  if [[ -z "${API_KEY:-}" ]]; then
    echo "Error: No API key found for workspace '${AN_ENV}'." >&2
    echo "Set ATOMICNEBULA_API_KEY or configure ${AN_ASSISTANT_CONFIG_FILE}." >&2
    exit 1
  fi
}

get_context() {
  local noun="$1"
  local id="$2"
  if [[ -z "$id" ]]; then
    echo "Error: ${noun} ID is required" >&2
    exit 1
  fi
  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Getting ${noun} context from ${BASE_URL}" >&2
  curl "${CURL_BASE[@]}" "${BASE_URL}/api/v1/atomicnebula/graph/${noun}/${id}" | jq .
}

bridge() {
  local from_type=""
  local from_id=""
  local to_type=""
  local to_id=""
  local max_hops=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from-type) from_type="$2"; shift 2 ;;
      --from-id) from_id="$2"; shift 2 ;;
      --to-type) to_type="$2"; shift 2 ;;
      --to-id) to_id="$2"; shift 2 ;;
      --max-hops) max_hops="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$from_type" || -z "$from_id" || -z "$to_type" || -z "$to_id" ]]; then
    echo "Error: bridge requires --from-type, --from-id, --to-type, and --to-id" >&2
    exit 1
  fi

  jq -n \
    --arg fromType "$from_type" \
    --arg fromId "$from_id" \
    --arg toType "$to_type" \
    --arg toId "$to_id" \
    --arg maxHops "$max_hops" \
    '{
      from: { nodeType: $fromType, nodeId: $fromId },
      to: { nodeType: $toType, nodeId: $toId },
      maxHops: (if $maxHops == "" then null else ($maxHops | tonumber) end)
    } | with_entries(select(.value != null))' \
    | curl "${CURL_BASE[@]}" -X POST --data @- "${BASE_URL}/api/v1/atomicnebula/graph/bridge" \
    | jq .
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" || -z "${1:-}" ]]; then
  usage
  exit 0
fi

require_api_key

case "${1:-}" in
  person) shift; get_context "person" "${1:-}" ;;
  thread) shift; get_context "thread" "${1:-}" ;;
  deal) shift; get_context "deal" "${1:-}" ;;
  project) shift; get_context "project" "${1:-}" ;;
  bridge) shift; bridge "$@" ;;
  intention)
    echo "Error: graph intention is not exposed until the backend route exists." >&2
    exit 1
    ;;
  *) echo "Error: unknown command '$1'" >&2; usage; exit 1 ;;
esac

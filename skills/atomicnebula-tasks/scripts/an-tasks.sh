#!/bin/bash
#
# Atomic Nebula Tasks CLI Helper
#
# A convenience script for querying Atomic Nebula tasks, projects, subtasks, and comments.
# Supports multi-workspace targeting via --env flag.
#

set -euo pipefail

# Source shared env resolver in a way that works on Lumen and from local consumer views
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

source "${RESOLVE_ENV_SH}"

# Extract --env flag before any other arg parsing
eval "$(extract_env_flag "$@")"

# Resolve workspace (sets BASE_URL, API_KEY, AN_ENV)
resolve_an_env "$ENV_ARG"

# Handle help early before requiring API key
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "help" ]]; then
  cat << 'USAGE'
Atomic Nebula Tasks CLI

Usage: an-tasks.sh [--env <workspace>] <command> [options]

Commands:
  list              List tasks with optional filters
  get <uuid>        Get full task details (use UUID from list)
  subtasks <uuid>   Get subtasks for a task
  comments <uuid>   Get comments for a task
  projects          List projects

Global Options:
  --env <env>          Target workspace slug (e.g., spider, dev, circeaurasupport)

List Options:
  --project <id>       Filter by project ID
  --owner <id>         Filter by owner/assignee ID
  --priority <value>   Filter by priority (high, medium, low)
  --status <id>        Filter by lifecycle stage ID
  --category <value>   Filter by category
  --contact <id>       Filter by contact ID
  --company <id>       Filter by company ID
  --deal <id>          Filter by deal ID
  --due-before <date>  Filter by due date (ISO format)
  --due-after <date>   Filter by due date (ISO format)
  --search <term>      Search in title/description
  --limit <n>          Max results (default: 50)
  --offset <n>         Pagination offset (default: 0)

Workspace Config:
  API keys resolve from env vars, assistant-workspaces.json, or legacy OpenClaw config.
  Fallback env vars:
    ATOMICNEBULA_API_KEY / ATOMICNEBULA_BASE_URL (production)
    ATOMICNEBULA_DEV_API_KEY / ATOMICNEBULA_DEV_BASE_URL (dev)

Examples:
  # List all tasks
  an-tasks.sh list

  # List high priority tasks on dev
  an-tasks.sh --env dev list --priority high

  # Get task details (use UUID from list output)
  an-tasks.sh get f7388c6a-c718-4584-bfe3-c5b6b4a8fe41
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

usage() {
  cat << EOF
Atomic Nebula Tasks CLI

Usage: $(basename "$0") [--env <workspace>] <command> [options]

Commands:
  list              List tasks with optional filters
  get <uuid>        Get full task details (use UUID from list)
  subtasks <uuid>   Get subtasks for a task
  comments <uuid>   Get comments for a task
  projects          List projects

Global Options:
  --env <env>          Target workspace slug (e.g., spider, dev, circeaurasupport)

List Options:
  --project <id>       Filter by project ID
  --owner <id>         Filter by owner/assignee ID
  --priority <value>   Filter by priority (high, medium, low)
  --status <id>        Filter by lifecycle stage ID
  --category <value>   Filter by category
  --contact <id>       Filter by contact ID
  --company <id>       Filter by company ID
  --deal <id>          Filter by deal ID
  --due-before <date>  Filter by due date (ISO format)
  --due-after <date>   Filter by due date (ISO format)
  --search <term>      Search in title/description
  --limit <n>          Max results (default: 50)
  --offset <n>         Pagination offset (default: 0)

Examples:
  # List all tasks
  $(basename "$0") list

  # List high priority tasks on dev
  $(basename "$0") --env dev list --priority high

  # Get task details (use UUID from list output)
  $(basename "$0") get f7388c6a-c718-4584-bfe3-c5b6b4a8fe41

  # Get subtasks and comments
  $(basename "$0") subtasks f7388c6a-c718-4584-bfe3-c5b6b4a8fe41
  $(basename "$0") comments f7388c6a-c718-4584-bfe3-c5b6b4a8fe41

  # List active projects
  $(basename "$0") projects
EOF
}

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
      --project) add_param "projectId" "$2"; shift 2 ;;
      --owner) add_param "ownerId" "$2"; shift 2 ;;
      --priority) add_param "priority" "$2"; shift 2 ;;
      --status) add_param "lifecycleStageId" "$2"; shift 2 ;;
      --category) add_param "category" "$2"; shift 2 ;;
      --contact) add_param "contactId" "$2"; shift 2 ;;
      --company) add_param "companyId" "$2"; shift 2 ;;
      --deal) add_param "dealId" "$2"; shift 2 ;;
      --due-before) add_param "dueBefore" "$2"; shift 2 ;;
      --due-after) add_param "dueAfter" "$2"; shift 2 ;;
      --search) add_param "searchTerm" "$2"; shift 2 ;;
      --limit) add_param "limit" "$2"; shift 2 ;;
      --offset) add_param "offset" "$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  echo "$query"
}

list_tasks() {
  local query
  query=$(build_query_string "$@")
  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Listing tasks from ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" "${BASE_URL}/api/v1/atomicnebula/tasks${query}" | jq .
}

get_task() {
  local task_id="$1"
  if [[ -z "$task_id" ]]; then
    echo "Error: task UUID is required" >&2
    exit 1
  fi
  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Getting task ${task_id} from ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" "${BASE_URL}/api/v1/atomicnebula/tasks/${task_id}" | jq .
}

get_subtasks() {
  local task_id="$1"
  if [[ -z "$task_id" ]]; then
    echo "Error: task UUID is required" >&2
    exit 1
  fi
  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Getting subtasks for ${task_id} from ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" "${BASE_URL}/api/v1/atomicnebula/tasks/${task_id}/subtasks" | jq .
}

get_comments() {
  local task_id="$1"
  if [[ -z "$task_id" ]]; then
    echo "Error: task UUID is required" >&2
    exit 1
  fi
  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Getting comments for ${task_id} from ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" "${BASE_URL}/api/v1/atomicnebula/tasks/${task_id}/comments" | jq .
}

list_projects() {
  local query=""
  local status=""
  local owner=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status) status="$2"; shift 2 ;;
      --owner) owner="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -n "$status" ]] || [[ -n "$owner" ]]; then
    query="?"
    [[ -n "$status" ]] && query+="status=$(printf '%s' "$status" | jq -sRr @uri)"
    [[ -n "$status" ]] && [[ -n "$owner" ]] && query+="&"
    [[ -n "$owner" ]] && query+="ownerId=$(printf '%s' "$owner" | jq -sRr @uri)"
  fi

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Listing projects from ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" "${BASE_URL}/api/v1/atomicnebula/projects${query}" | jq .
}

# Main command parser
case "${1:-}" in
  list)
    shift
    list_tasks "$@"
    ;;
  get)
    shift
    get_task "$@"
    ;;
  subtasks)
    shift
    get_subtasks "$@"
    ;;
  comments)
    shift
    get_comments "$@"
    ;;
  projects)
    shift
    list_projects "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  "")
    usage
    exit 1
    ;;
  *)
    echo "Error: Unknown command '$1'" >&2
    usage
    exit 1
    ;;
esac

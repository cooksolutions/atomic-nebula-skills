#!/bin/bash
#
# Atomic Nebula Task Write CLI Helper
#
# A convenience script for creating, updating, and completing tasks in Atomic Nebula.
# All write operations require approval via the Skill/Gateway workflow.
# Supports multi-workspace targeting via --env flag.
#
# Correlation: generates a UUID per invocation (RUN_ID), passes it as X-Run-Id header.
# On 402 (approval required), captures challengeId from response and writes both to
# write-runs.log for the webhook plugin to correlate back to the agent session.
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

# Generate a UUID for correlation with the webhook handler
RUN_ID=$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "run-$(date +%s)-$$")
WRITE_RUNS_LOG="${HOME}/.openclaw/logs/write-runs.log"

# Handle help early before requiring API key
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "help" ]]; then
  cat << 'USAGE'
Atomic Nebula Task Write CLI

Usage: an-task-write.sh [--env <workspace>] <command> [options]

Commands:
  create             Create a new task
  update <taskId>    Update an existing task
  complete <taskId>  Mark a task as completed
  delete <taskId>    Soft delete a task
  create-project     Create a new project
  list-projects      List all projects

Global Options:
  --env <env>          Target workspace slug (e.g., spider, dev, circeaurasupport)

Create Options:
  --title <text>       Task title (required)
  --description <text> Task description
  --category <value>   Category (default: general)
  --priority <value>   Priority: high, medium, low (default: medium)
  --project <id>       Project ID
  --owner <id>         Assignee user ID
  --reporter <id>      Reporter user ID
  --due <date>         Due date (ISO format: YYYY-MM-DD)
  --start <date>       Start date (ISO format: YYYY-MM-DD)
  --contact <id>       Linked contact ID
  --company <id>       Linked company ID
  --deal <id>          Linked deal ID
  --labels <csv>       Comma-separated labels

Update Options:
  Same as create options, plus:
  --complete           Mark as completed

Create Project Options:
  --name <text>        Project name (required)
  --key <text>         Project key (auto-generated from name if omitted)
  --description <text> Project description
  --status <value>     Project status
  --start <date>       Start date (ISO format: YYYY-MM-DD)
  --target-end <date>  Target end date (ISO format: YYYY-MM-DD)

Workspace Config:
  API keys resolve from env vars, assistant-workspaces.json, or legacy OpenClaw config.
  Fallback env vars:
    ATOMICNEBULA_API_KEY / ATOMICNEBULA_BASE_URL (production)
    ATOMICNEBULA_DEV_API_KEY / ATOMICNEBULA_DEV_BASE_URL (dev)

Examples:
  # Create a high priority task
  an-task-write.sh create --title "Review report" --priority high --due 2026-02-28

  # Create a task on dev
  an-task-write.sh --env dev create --title "Test task" --priority low

  # Assign a task
  an-task-write.sh update TASK-0042 --owner user_xyz

  # Complete a task
  an-task-write.sh complete TASK-0042

  # Delete a task
  an-task-write.sh delete TASK-0042

Approval Workflow:
  All write operations require human approval before execution.
  The operation will be queued for review and executed upon approval.
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

# Common curl options — includes X-Run-Id for webhook correlation
CURL_OPTS=(-s -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" -H "X-Run-Id: $RUN_ID")

# Show active workspace for non-default
ENV_PREFIX=$(print_env_prefix)

# Generate idempotency key
generate_idempotency_key() {
  echo "task-create-$(date +%Y%m%d%H%M%S)-$(jot -r 1 1000 9999 2>/dev/null || shuf -i 1000-9999 -n 1 2>/dev/null || echo $$)"
}

# Handle curl response: check status, log approval challenges for webhook correlation
# Arguments: $1 = full response (body + status), $2 = action name
handle_response() {
  local full_response="$1"
  local action="$2"

  # Extract HTTP status code (last line) and body (everything before)
  local http_code
  http_code=$(echo "$full_response" | tail -1)
  local body
  body=$(echo "$full_response" | sed '$d')

  # Detect approval required: HTTP 402 OR APPROVAL_REQUIRED in response body
  # (Convex HTTP handlers may return non-402 status with approval challenge in body)
  local is_approval=""
  if [[ "$http_code" == "402" ]]; then
    is_approval="true"
  elif echo "$body" | grep -q '"APPROVAL_REQUIRED"' 2>/dev/null; then
    is_approval="true"
  fi

  if [[ -n "$is_approval" ]]; then
    # Extract challengeId — try top-level first, then error.details (Convex response structure)
    local challenge_id
    challenge_id=$(echo "$body" | jq -r '.challengeId // .error.details.challengeId // empty' 2>/dev/null || true)
    local approval_url
    approval_url=$(echo "$body" | jq -r '.approvalUrl // .error.details.approvalUrl // empty' 2>/dev/null || true)

    # Write structured log entry for webhook correlation
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
    if [[ -n "${approval_url:-}" ]]; then
      echo "Approve at: $approval_url"
    fi
    echo ""
    echo "$body" | jq . 2>/dev/null || echo "$body"
  else
    # Non-approval response — output normally
    echo "$body" | jq . 2>/dev/null || echo "$body"
  fi
}

# Build JSON for create/update
build_task_json() {
  local json="{}"

  add_field() {
    local key="$1"
    local value="$2"
    if [[ -n "$value" ]]; then
      json=$(echo "$json" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')
    fi
  }

  add_field_number() {
    local key="$1"
    local value="$2"
    if [[ -n "$value" ]]; then
      json=$(echo "$json" | jq --arg k "$key" --argjson v "$value" '. + {($k): $v}')
    fi
  }

  add_field_array() {
    local key="$1"
    local value="$2"
    if [[ -n "$value" ]]; then
      # Convert CSV to JSON array
      local arr
      arr=$(echo "$value" | tr ',' '\n' | jq -R . | jq -s .)
      json=$(echo "$json" | jq --arg k "$key" --argjson v "$arr" '. + {($k): $v}')
    fi
  }

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) add_field "title" "$2"; shift 2 ;;
      --description) add_field "description" "$2"; shift 2 ;;
      --category) add_field "category" "$2"; shift 2 ;;
      --priority) add_field "priority" "$2"; shift 2 ;;
      --project) add_field "projectId" "$2"; shift 2 ;;
      --owner) add_field "ownerId" "$2"; shift 2 ;;
      --reporter) add_field "reporterId" "$2"; shift 2 ;;
      --due) add_field "dueDate" "$2"; shift 2 ;;
      --start) add_field "startDate" "$2"; shift 2 ;;
      --contact) add_field "contactId" "$2"; shift 2 ;;
      --company) add_field "companyId" "$2"; shift 2 ;;
      --deal) add_field "dealId" "$2"; shift 2 ;;
      --labels) add_field_array "labels" "$2"; shift 2 ;;
      --complete)
        local now_ms=$(( $(date +%s) * 1000 ))
        json=$(echo "$json" | jq --argjson completed "$now_ms" '. + {completedAt: $completed}')
        shift
        ;;
      *) shift ;;
    esac
  done

  echo "$json"
}

create_task() {
  local title=""
  local json

  # Check for title
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; break ;;
      *) shift ;;
    esac
  done

  if [[ -z "$title" ]]; then
    echo "Error: --title is required for create" >&2
    exit 1
  fi

  json=$(build_task_json "$@")
  local idempotency_key
  idempotency_key=$(generate_idempotency_key)

  echo "${ENV_PREFIX}Creating task with approval workflow..."
  echo "Idempotency key: $idempotency_key"
  echo "Run ID: $RUN_ID"
  echo "Payload: $json"
  echo ""

  local response
  response=$(curl "${CURL_OPTS[@]}" \
    -H "X-Idempotency-Key: $idempotency_key" \
    -w "\n%{http_code}" \
    -X POST \
    -d "$json" \
    "${BASE_URL}/api/v1/atomicnebula/tasks")

  handle_response "$response" "create"
}

update_task() {
  local task_id="$1"
  if [[ -z "$task_id" ]]; then
    echo "Error: taskId is required" >&2
    exit 1
  fi
  shift

  local json
  json=$(build_task_json "$@")

  if [[ "$json" == "{}" ]]; then
    echo "Error: No update fields provided" >&2
    exit 1
  fi

  echo "${ENV_PREFIX}Updating task $task_id with approval workflow..."
  echo "Run ID: $RUN_ID"
  echo "Payload: $json"
  echo ""

  local response
  response=$(curl "${CURL_OPTS[@]}" \
    -w "\n%{http_code}" \
    -X PATCH \
    -d "$json" \
    "${BASE_URL}/api/v1/atomicnebula/tasks/${task_id}")

  handle_response "$response" "update"
}

complete_task() {
  local task_id="$1"
  if [[ -z "$task_id" ]]; then
    echo "Error: taskId is required" >&2
    exit 1
  fi

  local now_ms=$(( $(date +%s) * 1000 ))
  local json="{\"completedAt\": ${now_ms}}"

  echo "${ENV_PREFIX}Completing task $task_id with approval workflow..."
  echo "Run ID: $RUN_ID"
  echo ""

  local response
  response=$(curl "${CURL_OPTS[@]}" \
    -w "\n%{http_code}" \
    -X PATCH \
    -d "$json" \
    "${BASE_URL}/api/v1/atomicnebula/tasks/${task_id}")

  handle_response "$response" "complete"
}

delete_task() {
  local task_id="$1"
  if [[ -z "$task_id" ]]; then
    echo "Error: taskId is required" >&2
    exit 1
  fi

  echo "${ENV_PREFIX}Deleting task $task_id with approval workflow..."
  echo "Run ID: $RUN_ID"
  echo ""

  local response
  response=$(curl "${CURL_OPTS[@]}" \
    -w "\n%{http_code}" \
    -X DELETE \
    "${BASE_URL}/api/v1/atomicnebula/tasks/${task_id}")

  handle_response "$response" "delete"
}

list_projects() {
  echo "${ENV_PREFIX}Listing projects..."
  echo ""

  local response
  response=$(curl "${CURL_OPTS[@]}" \
    -w "\n%{http_code}" \
    -X GET \
    "${BASE_URL}/api/v1/atomicnebula/projects")

  handle_response "$response" "list-projects"
}

create_project() {
  local name=""
  local key=""
  local description=""
  local status=""
  local start_date=""
  local target_end_date=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --key) key="$2"; shift 2 ;;
      --description) description="$2"; shift 2 ;;
      --status) status="$2"; shift 2 ;;
      --start) start_date="$2"; shift 2 ;;
      --target-end) target_end_date="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$name" ]]; then
    echo "Error: --name is required for create-project" >&2
    exit 1
  fi

  # Auto-generate key from name if not provided (lowercase, hyphens, no special chars)
  if [[ -z "$key" ]]; then
    key=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
  fi

  local json="{}"
  json=$(echo "$json" | jq --arg v "$name" '. + {name: $v}')
  json=$(echo "$json" | jq --arg v "$key" '. + {key: $v}')
  [[ -n "$description" ]] && json=$(echo "$json" | jq --arg v "$description" '. + {description: $v}')
  [[ -n "$status" ]] && json=$(echo "$json" | jq --arg v "$status" '. + {status: $v}')
  [[ -n "$start_date" ]] && json=$(echo "$json" | jq --arg v "$start_date" '. + {startDate: $v}')
  [[ -n "$target_end_date" ]] && json=$(echo "$json" | jq --arg v "$target_end_date" '. + {targetEndDate: $v}')

  echo "${ENV_PREFIX}Creating project with approval workflow..."
  echo "Run ID: $RUN_ID"
  echo "Payload: $json"
  echo ""

  local response
  response=$(curl "${CURL_OPTS[@]}" \
    -w "\n%{http_code}" \
    -X POST \
    -d "$json" \
    "${BASE_URL}/api/v1/atomicnebula/projects")

  handle_response "$response" "create-project"
}

# Main command parser
case "${1:-}" in
  create)
    shift
    create_task "$@"
    ;;
  update)
    shift
    update_task "$@"
    ;;
  complete)
    shift
    complete_task "$@"
    ;;
  delete)
    shift
    delete_task "$@"
    ;;
  create-project)
    shift
    create_project "$@"
    ;;
  list-projects)
    shift
    list_projects "$@"
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

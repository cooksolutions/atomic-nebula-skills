#!/bin/bash
#
# Atomic Nebula Forms CLI Helper
#
# A convenience script for managing forms and querying submissions in Atomic Nebula.
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
Atomic Nebula Forms CLI

Usage: an-forms.sh [--env <workspace>] <command> [options]

Commands:
  list                       List forms with optional filters
  get <uuid>                 Get full form details
  create                     Create a new form
  update <uuid>              Update an existing form
  publish <uuid>             Publish a form (make it publicly accessible)
  unpublish <uuid>           Unpublish a form (remove public access)
  delete <uuid>              Delete a form (soft delete)
  responses <form-uuid>      List submissions for a form
  response <response-uuid>   Get a single submission

Global Options:
  --env <env>          Target workspace slug (e.g., spider, dev, circeaurasupport)

List Options:
  --active             Filter to active forms only
  --inactive           Filter to inactive forms only
  --published          Filter to published forms only
  --unpublished        Filter to unpublished forms only
  --limit <n>          Max results (default: 50)

Create Options:
  --name <name>        Form name (required)
  --description <desc> Form description
  --type <type>        Form type (default: multi-step)
  --steps-json <json>  Steps as inline JSON string
  --steps-file <path>  Steps from a JSON file

Update Options:
  --name <name>        New form name
  --description <desc> New description
  --type <type>        New form type
  --steps-json <json>  Replace steps with inline JSON
  --steps-file <path>  Replace steps from a JSON file
  --active             Set form as active
  --inactive           Set form as inactive

Response Options:
  --from <date>        Filter from date (ISO format)
  --to <date>          Filter to date (ISO format)
  --limit <n>          Max results (default: 50)

Examples:
  # List all forms
  an-forms.sh list

  # List published forms on dev
  an-forms.sh --env dev list --published

  # Create a simple form
  an-forms.sh create --name "Feedback" --steps-json '[{"id":"s1","title":"Feedback","position":0,"fields":[{"id":"msg","type":"textarea","label":"Message","required":true}]}]'

  # Publish a form
  an-forms.sh publish f7388c6a-c718-4584-bfe3-c5b6b4a8fe41

  # List submissions
  an-forms.sh responses f7388c6a-c718-4584-bfe3-c5b6b4a8fe41
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

FORMS_URL="${BASE_URL}/api/v1/atomicnebula/forms"

# --- Commands ---

list_forms() {
  local query=""
  local first=1

  add_param() {
    local key="$1" value="$2"
    if [[ -n "$value" ]]; then
      if [[ $first -eq 1 ]]; then
        query="?${key}=$(printf '%s' "$value" | jq -sRr @uri)"
        first=0
      else
        query+="&${key}=$(printf '%s' "$value" | jq -sRr @uri)"
      fi
    fi
  }

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --active)      add_param "isActive" "true"; shift ;;
      --inactive)    add_param "isActive" "false"; shift ;;
      --published)   add_param "isPublished" "true"; shift ;;
      --unpublished) add_param "isPublished" "false"; shift ;;
      --limit)       add_param "limit" "$2"; shift 2 ;;
      --cursor)      add_param "cursor" "$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Listing forms from ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" "${FORMS_URL}${query}" | jq .
}

get_form() {
  local form_id="${1:-}"
  if [[ -z "$form_id" ]]; then
    echo "Error: form UUID is required" >&2
    exit 1
  fi
  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Getting form ${form_id} from ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" "${FORMS_URL}/${form_id}" | jq .
}

create_form() {
  local name="" description="" type="" steps_json="" steps_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)        name="$2"; shift 2 ;;
      --description) description="$2"; shift 2 ;;
      --type)        type="$2"; shift 2 ;;
      --steps-json)  steps_json="$2"; shift 2 ;;
      --steps-file)  steps_file="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$name" ]]; then
    echo "Error: --name is required" >&2
    exit 1
  fi

  # Resolve steps
  local steps=""
  if [[ -n "$steps_file" ]]; then
    if [[ ! -f "$steps_file" ]]; then
      echo "Error: steps file not found: $steps_file" >&2
      exit 1
    fi
    steps=$(cat "$steps_file")
  elif [[ -n "$steps_json" ]]; then
    steps="$steps_json"
  else
    echo "Error: --steps-json or --steps-file is required" >&2
    exit 1
  fi

  # Validate steps is valid JSON array
  if ! echo "$steps" | jq empty 2>/dev/null; then
    echo "Error: steps is not valid JSON" >&2
    exit 1
  fi

  # Build request body
  local body
  body=$(jq -n \
    --arg name "$name" \
    --arg description "$description" \
    --arg type "$type" \
    --argjson steps "$steps" \
    '{
      name: $name,
      steps: $steps
    }
    + (if $description != "" then {description: $description} else {} end)
    + (if $type != "" then {type: $type} else {} end)')

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Creating form '${name}' on ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" -X POST "${FORMS_URL}" -d "$body" | jq .
}

update_form() {
  local form_id="${1:-}"
  if [[ -z "$form_id" ]]; then
    echo "Error: form UUID is required" >&2
    exit 1
  fi
  shift

  local name="" description="" type="" steps_json="" steps_file="" is_active=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)        name="$2"; shift 2 ;;
      --description) description="$2"; shift 2 ;;
      --type)        type="$2"; shift 2 ;;
      --steps-json)  steps_json="$2"; shift 2 ;;
      --steps-file)  steps_file="$2"; shift 2 ;;
      --active)      is_active="true"; shift ;;
      --inactive)    is_active="false"; shift ;;
      *) shift ;;
    esac
  done

  # Resolve steps if provided
  local steps=""
  if [[ -n "$steps_file" ]]; then
    if [[ ! -f "$steps_file" ]]; then
      echo "Error: steps file not found: $steps_file" >&2
      exit 1
    fi
    steps=$(cat "$steps_file")
  elif [[ -n "$steps_json" ]]; then
    steps="$steps_json"
  fi

  # Build request body with only provided fields
  local body="{}"
  if [[ -n "$name" ]]; then
    body=$(echo "$body" | jq --arg v "$name" '. + {name: $v}')
  fi
  if [[ -n "$description" ]]; then
    body=$(echo "$body" | jq --arg v "$description" '. + {description: $v}')
  fi
  if [[ -n "$type" ]]; then
    body=$(echo "$body" | jq --arg v "$type" '. + {type: $v}')
  fi
  if [[ -n "$steps" ]]; then
    body=$(echo "$body" | jq --argjson v "$steps" '. + {steps: $v}')
  fi
  if [[ -n "$is_active" ]]; then
    body=$(echo "$body" | jq --argjson v "$is_active" '. + {isActive: $v}')
  fi

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Updating form ${form_id} on ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" -X PATCH "${FORMS_URL}/${form_id}" -d "$body" | jq .
}

publish_form() {
  local form_id="${1:-}"
  if [[ -z "$form_id" ]]; then
    echo "Error: form UUID is required" >&2
    exit 1
  fi
  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Publishing form ${form_id} on ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" -X POST "${FORMS_URL}/${form_id}/publish" | jq .
}

unpublish_form() {
  local form_id="${1:-}"
  if [[ -z "$form_id" ]]; then
    echo "Error: form UUID is required" >&2
    exit 1
  fi
  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Unpublishing form ${form_id} on ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" -X POST "${FORMS_URL}/${form_id}/unpublish" | jq .
}

delete_form() {
  local form_id="${1:-}"
  if [[ -z "$form_id" ]]; then
    echo "Error: form UUID is required" >&2
    exit 1
  fi
  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Deleting form ${form_id} on ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" -X DELETE "${FORMS_URL}/${form_id}" | jq .
}

list_responses() {
  local form_id="${1:-}"
  if [[ -z "$form_id" ]]; then
    echo "Error: form UUID is required" >&2
    exit 1
  fi
  shift

  local query=""
  local first=1

  add_param() {
    local key="$1" value="$2"
    if [[ -n "$value" ]]; then
      if [[ $first -eq 1 ]]; then
        query="?${key}=$(printf '%s' "$value" | jq -sRr @uri)"
        first=0
      else
        query+="&${key}=$(printf '%s' "$value" | jq -sRr @uri)"
      fi
    fi
  }

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from)   add_param "fromDate" "$2"; shift 2 ;;
      --to)     add_param "toDate" "$2"; shift 2 ;;
      --limit)  add_param "limit" "$2"; shift 2 ;;
      --cursor) add_param "cursor" "$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Listing responses for form ${form_id} from ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" "${FORMS_URL}/${form_id}/responses${query}" | jq .
}

get_response() {
  local response_id="${1:-}"
  if [[ -z "$response_id" ]]; then
    echo "Error: response UUID is required" >&2
    exit 1
  fi
  # Response endpoint requires a form ID in the path, but we look it up via
  # the generic responses path. Since the GET handler dispatches on the last
  # path segment being under /responses/, we use a placeholder form ID and
  # the actual response ID.
  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Getting response ${response_id} from ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" "${FORMS_URL}/_/responses/${response_id}" | jq .
}

# Main command parser
case "${1:-}" in
  list)
    shift
    list_forms "$@"
    ;;
  get)
    shift
    get_form "$@"
    ;;
  create)
    shift
    create_form "$@"
    ;;
  update)
    shift
    update_form "$@"
    ;;
  publish)
    shift
    publish_form "$@"
    ;;
  unpublish)
    shift
    unpublish_form "$@"
    ;;
  delete)
    shift
    delete_form "$@"
    ;;
  responses)
    shift
    list_responses "$@"
    ;;
  response)
    shift
    get_response "$@"
    ;;
  -h|--help|help)
    cat << 'USAGE'
Usage: an-forms.sh [--env <workspace>] <command> [options]
Run 'an-forms.sh help' for full usage.
USAGE
    exit 0
    ;;
  "")
    echo "Error: No command specified. Run 'an-forms.sh help' for usage." >&2
    exit 1
    ;;
  *)
    echo "Error: Unknown command '$1'. Run 'an-forms.sh help' for usage." >&2
    exit 1
    ;;
esac

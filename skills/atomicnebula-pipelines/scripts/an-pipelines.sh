#!/bin/bash
#
# Atomic Nebula Lifecycle Pipelines CLI Helper
#
# Read + write helpers for lifecycle pipelines and stages over the Atomic
# Nebula external REST API. Write operations require the
# `atomicnebula:lifecycle:write` permission on the API key.
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

CURL_BASE=(-s -H "Authorization: Bearer $API_KEY")
CURL_JSON=("${CURL_BASE[@]}" -H "Content-Type: application/json")

usage() {
  cat << 'USAGE'
Atomic Nebula Lifecycle Pipelines CLI

Usage: an-pipelines.sh [--env <workspace>] <command> [options]

Read commands:
  list                                  List pipelines (and stages)
  get <pipelineId>                      Get a single pipeline (metadata only)
  stages <pipelineId>                   Print stage id + name + displayOrder
  stage-id <pipelineId> <stageName>     Resolve a stage's id by name

Pipeline write commands:
  create-pipeline                       Create a new pipeline
    --object-type <type>                Required (task | deal | contact | company | lead)
    --name <text>                       Required
    --description <text>
    --is-default
    --transition-mode <mode>            open | sequential | explicit (default: open)
    --no-allow-backward                 Disable backward moves (sequential only)
  update-pipeline <pipelineId>          Update an existing pipeline
    --name <text>
    --description <text>
    --is-default | --no-default
    --transition-mode <mode>
    --no-allow-backward | --allow-backward
  delete-pipeline <pipelineId>          Soft-delete a pipeline (and all its stages)

Stage write commands:
  create-stage <pipelineId>             Append a stage to a pipeline
    --name <text>                       Required
    --description <text>
    --color <hex>
    --probability <0-100>
    --closed                            Mark as a closed stage
    --won                               Mark as a winning stage (deal pipelines)
    --reserves-stock                    Mark as reserving stock (deal pipelines)
  update-stage <pipelineId> <stageId>   Update an existing stage
    Same options as create-stage; pass only fields you want to change.
  delete-stage <pipelineId> <stageId>   Soft-delete a stage
  reorder-stages <pipelineId> <id1> <id2> ...
                                        Reorder stages 1-based by IDs in order

Global Options:
  --env <env>                  Target workspace (spider | dev | circeaurasupport)

Examples:
  an-pipelines.sh list --object-type task
  an-pipelines.sh create-pipeline --object-type task --name "Software Development"
  an-pipelines.sh create-stage abc-123 --name "Backlog" --color "#fab"
  an-pipelines.sh stage-id abc-123 "In Progress"
USAGE
}

# Helper: build a JSON object from key=value pairs using jq
build_json() {
  local jq_expr="."
  local args=()
  while [[ $# -gt 0 ]]; do
    args+=("--arg" "$1" "$2")
    jq_expr+=" | .${1}=\$${1}"
    shift 2
  done
  echo "{}" | jq "${args[@]}" "$jq_expr"
}

list_pipelines() {
  local object_type=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --object-type) object_type="$2"; shift 2;;
      *) echo "Unknown option: $1" >&2; exit 2;;
    esac
  done
  local url="${BASE_URL}/api/v1/atomicnebula/lifecycle-pipelines"
  [[ -n "$object_type" ]] && url="${url}?objectType=${object_type}"
  curl "${CURL_BASE[@]}" "$url" | jq .
}

get_pipeline() {
  local pid="${1:-}"; [[ -z "$pid" ]] && { echo "Missing pipelineId" >&2; exit 2; }
  curl "${CURL_BASE[@]}" "${BASE_URL}/api/v1/atomicnebula/lifecycle-pipelines/${pid}" | jq .
}

list_stages() {
  local pid="${1:-}"; [[ -z "$pid" ]] && { echo "Missing pipelineId" >&2; exit 2; }
  curl "${CURL_BASE[@]}" "${BASE_URL}/api/v1/atomicnebula/lifecycle-pipelines" \
    | jq --arg pid "$pid" '.data.items[] | select(.id == $pid) | .stages[] | {id, name, displayOrder, isClosed}'
}

resolve_stage_id() {
  local pid="${1:-}" sn="${2:-}"
  [[ -z "$pid" || -z "$sn" ]] && { echo "Usage: stage-id <pipelineId> <stageName>" >&2; exit 2; }
  curl "${CURL_BASE[@]}" "${BASE_URL}/api/v1/atomicnebula/lifecycle-pipelines" \
    | jq -r --arg pid "$pid" --arg sn "$sn" \
        '.data.items[] | select(.id == $pid) | .stages[] | select(.name == $sn) | .id'
}

create_pipeline() {
  local object_type="" name="" description="" is_default=""
  local transition_mode="open" allow_backward=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --object-type) object_type="$2"; shift 2;;
      --name) name="$2"; shift 2;;
      --description) description="$2"; shift 2;;
      --is-default) is_default="true"; shift;;
      --transition-mode) transition_mode="$2"; shift 2;;
      --no-allow-backward) allow_backward="false"; shift;;
      *) echo "Unknown option: $1" >&2; exit 2;;
    esac
  done
  [[ -z "$object_type" ]] && { echo "--object-type required" >&2; exit 2; }
  [[ -z "$name" ]] && { echo "--name required" >&2; exit 2; }

  local body
  body=$(jq -n \
    --arg objectType "$object_type" \
    --arg name "$name" \
    --arg description "$description" \
    --arg transitionMode "$transition_mode" \
    --argjson isDefault "${is_default:-null}" \
    --argjson allowBackwardMoves "${allow_backward:-null}" \
    '{ objectType: $objectType, name: $name, transitionMode: $transitionMode }
     + (if $description != "" then { description: $description } else {} end)
     + (if $isDefault != null then { isDefault: $isDefault } else {} end)
     + (if $allowBackwardMoves != null then { allowBackwardMoves: $allowBackwardMoves } else {} end)')

  curl "${CURL_JSON[@]}" -X POST -d "$body" \
    "${BASE_URL}/api/v1/atomicnebula/lifecycle-pipelines" | jq .
}

update_pipeline() {
  local pid="${1:-}"; [[ -z "$pid" ]] && { echo "Missing pipelineId" >&2; exit 2; }
  shift
  local name="" description="" is_default="" transition_mode="" allow_backward=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2;;
      --description) description="$2"; shift 2;;
      --is-default) is_default="true"; shift;;
      --no-default) is_default="false"; shift;;
      --transition-mode) transition_mode="$2"; shift 2;;
      --no-allow-backward) allow_backward="false"; shift;;
      --allow-backward) allow_backward="true"; shift;;
      *) echo "Unknown option: $1" >&2; exit 2;;
    esac
  done

  local body
  body=$(jq -n \
    --arg name "$name" \
    --arg description "$description" \
    --arg transitionMode "$transition_mode" \
    --argjson isDefault "${is_default:-null}" \
    --argjson allowBackwardMoves "${allow_backward:-null}" \
    '{}
     + (if $name != "" then { name: $name } else {} end)
     + (if $description != "" then { description: $description } else {} end)
     + (if $transitionMode != "" then { transitionMode: $transitionMode } else {} end)
     + (if $isDefault != null then { isDefault: $isDefault } else {} end)
     + (if $allowBackwardMoves != null then { allowBackwardMoves: $allowBackwardMoves } else {} end)')

  curl "${CURL_JSON[@]}" -X PATCH -d "$body" \
    "${BASE_URL}/api/v1/atomicnebula/lifecycle-pipelines/${pid}" | jq .
}

delete_pipeline() {
  local pid="${1:-}"; [[ -z "$pid" ]] && { echo "Missing pipelineId" >&2; exit 2; }
  curl "${CURL_JSON[@]}" -X DELETE \
    "${BASE_URL}/api/v1/atomicnebula/lifecycle-pipelines/${pid}" -w "\nHTTP %{http_code}\n"
}

create_stage() {
  local pid="${1:-}"; [[ -z "$pid" ]] && { echo "Missing pipelineId" >&2; exit 2; }
  shift
  local name="" description="" color="" probability="" is_closed="" is_won="" reserves_stock=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2;;
      --description) description="$2"; shift 2;;
      --color) color="$2"; shift 2;;
      --probability) probability="$2"; shift 2;;
      --closed) is_closed="true"; shift;;
      --won) is_won="true"; shift;;
      --reserves-stock) reserves_stock="true"; shift;;
      *) echo "Unknown option: $1" >&2; exit 2;;
    esac
  done
  [[ -z "$name" ]] && { echo "--name required" >&2; exit 2; }

  local body
  body=$(jq -n \
    --arg name "$name" \
    --arg description "$description" \
    --arg color "$color" \
    --argjson probability "${probability:-null}" \
    --argjson isClosed "${is_closed:-null}" \
    --argjson isWon "${is_won:-null}" \
    --argjson reservesStock "${reserves_stock:-null}" \
    '{ name: $name }
     + (if $description != "" then { description: $description } else {} end)
     + (if $color != "" then { color: $color } else {} end)
     + (if $probability != null then { probability: $probability } else {} end)
     + (if $isClosed != null then { isClosed: $isClosed } else {} end)
     + (if $isWon != null then { isWon: $isWon } else {} end)
     + (if $reservesStock != null then { reservesStock: $reservesStock } else {} end)')

  curl "${CURL_JSON[@]}" -X POST -d "$body" \
    "${BASE_URL}/api/v1/atomicnebula/lifecycle-pipelines/${pid}/stages" | jq .
}

update_stage() {
  local pid="${1:-}" sid="${2:-}"
  [[ -z "$pid" || -z "$sid" ]] && { echo "Usage: update-stage <pipelineId> <stageId>" >&2; exit 2; }
  shift 2
  local name="" description="" color="" probability="" is_closed="" is_won="" reserves_stock=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2;;
      --description) description="$2"; shift 2;;
      --color) color="$2"; shift 2;;
      --probability) probability="$2"; shift 2;;
      --closed) is_closed="true"; shift;;
      --not-closed) is_closed="false"; shift;;
      --won) is_won="true"; shift;;
      --not-won) is_won="false"; shift;;
      --reserves-stock) reserves_stock="true"; shift;;
      --no-reserves-stock) reserves_stock="false"; shift;;
      *) echo "Unknown option: $1" >&2; exit 2;;
    esac
  done

  local body
  body=$(jq -n \
    --arg name "$name" \
    --arg description "$description" \
    --arg color "$color" \
    --argjson probability "${probability:-null}" \
    --argjson isClosed "${is_closed:-null}" \
    --argjson isWon "${is_won:-null}" \
    --argjson reservesStock "${reserves_stock:-null}" \
    '{}
     + (if $name != "" then { name: $name } else {} end)
     + (if $description != "" then { description: $description } else {} end)
     + (if $color != "" then { color: $color } else {} end)
     + (if $probability != null then { probability: $probability } else {} end)
     + (if $isClosed != null then { isClosed: $isClosed } else {} end)
     + (if $isWon != null then { isWon: $isWon } else {} end)
     + (if $reservesStock != null then { reservesStock: $reservesStock } else {} end)')

  curl "${CURL_JSON[@]}" -X PATCH -d "$body" \
    "${BASE_URL}/api/v1/atomicnebula/lifecycle-pipelines/${pid}/stages/${sid}" | jq .
}

delete_stage() {
  local pid="${1:-}" sid="${2:-}"
  [[ -z "$pid" || -z "$sid" ]] && { echo "Usage: delete-stage <pipelineId> <stageId>" >&2; exit 2; }
  curl "${CURL_JSON[@]}" -X DELETE \
    "${BASE_URL}/api/v1/atomicnebula/lifecycle-pipelines/${pid}/stages/${sid}" -w "\nHTTP %{http_code}\n"
}

reorder_stages() {
  local pid="${1:-}"; [[ -z "$pid" ]] && { echo "Missing pipelineId" >&2; exit 2; }
  shift
  local order_args=("$@")
  if [[ ${#order_args[@]} -eq 0 ]]; then
    echo "Usage: reorder-stages <pipelineId> <stageId1> <stageId2> ..." >&2
    exit 2
  fi
  local body
  body=$(printf '%s\n' "${order_args[@]}" | jq -R . | jq -s '{ stageOrder: . }')
  curl "${CURL_JSON[@]}" -X POST -d "$body" \
    "${BASE_URL}/api/v1/atomicnebula/lifecycle-pipelines/${pid}/stages/reorder" | jq .
}

cmd="${1:-}"
if [[ -z "$cmd" || "$cmd" == "-h" || "$cmd" == "--help" ]]; then
  usage
  exit 0
fi
shift || true

case "$cmd" in
  list)            list_pipelines "$@";;
  get)             get_pipeline "$@";;
  stages)          list_stages "$@";;
  stage-id)        resolve_stage_id "$@";;
  create-pipeline) create_pipeline "$@";;
  update-pipeline) update_pipeline "$@";;
  delete-pipeline) delete_pipeline "$@";;
  create-stage)    create_stage "$@";;
  update-stage)    update_stage "$@";;
  delete-stage)    delete_stage "$@";;
  reorder-stages)  reorder_stages "$@";;
  -h|--help|help)  usage;;
  *) echo "Unknown command: $cmd" >&2; echo >&2; usage >&2; exit 2;;
esac

#!/bin/bash
#
# Atomic Nebula Attachments CLI Helper
#
# Supports generic attachment operations across entity types:
#   upload, list, download-url, link, unlink
#
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
Atomic Nebula Attachments CLI

Usage: an-attachments.sh [--env <workspace>] <command> [options]

Commands:
  list                            List attachments for an entity
  upload                          Upload and confirm an attachment for an entity
  download-url <attachmentId>     Get a signed download URL for an attachment
  link <attachmentId>             Link an existing attachment to an entity
  unlink <attachmentId>           Unlink attachment from an entity

Global Options:
  --env <env>                     Target workspace slug (e.g., spider, dev, circeaurasupport)

Common Entity Options:
  --entity-type <type>            Entity type (task, contact, company, deal, etc.)
  --entity-id <id>                Entity ID

list Options:
  --include-pending               Include pending uploads

upload Options:
  --file <path>                   Local file path (required)
  --content-type <mime>           Override MIME type (default: inferred)
  --checksum <sha256>             Optional checksum

 download-url Options:
  --disposition <mode>            attachment|inline (default: attachment)

link Options:
  --relationship <mode>           primary|reference (default: reference)
  --order <number>                Optional display order

unlink Options:
  --hard-delete-if-orphan <bool>  true|false (default: true)

Examples:
  an-attachments.sh list --entity-type task --entity-id TASK-123
  an-attachments.sh upload --entity-type task --entity-id TASK-123 --file ./spec.pdf
  an-attachments.sh download-url att-123 --entity-type task --entity-id TASK-123
  an-attachments.sh link att-123 --entity-type deal --entity-id DEAL-42 --relationship reference
  an-attachments.sh unlink att-123 --entity-type task --entity-id TASK-123
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

require_entity() {
  local entity_type="$1"
  local entity_id="$2"
  if [[ -z "$entity_type" ]]; then
    echo "Error: --entity-type is required" >&2
    exit 1
  fi
  if [[ -z "$entity_id" ]]; then
    echo "Error: --entity-id is required" >&2
    exit 1
  fi
}

request_json() {
  local method="$1"
  local url="$2"
  local body="${3:-}"

  local response
  if [[ -n "$body" ]]; then
    response=$(curl "${CURL_BASE[@]}" -H "X-Run-Id: $RUN_ID" -w "\n%{http_code}" -X "$method" -d "$body" "$url")
  else
    response=$(curl "${CURL_BASE[@]}" -H "X-Run-Id: $RUN_ID" -w "\n%{http_code}" -X "$method" "$url")
  fi

  split_response "$response"
}

command_list() {
  local entity_type=""
  local entity_id=""
  local include_pending="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --entity-type) entity_type="$2"; shift 2 ;;
      --entity-id) entity_id="$2"; shift 2 ;;
      --include-pending) include_pending="true"; shift ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  require_entity "$entity_type" "$entity_id"

  local url="${BASE_URL}/api/v1/atomicnebula/attachments?entityType=${entity_type}&entityId=${entity_id}"
  if [[ "$include_pending" == "true" ]]; then
    url+="&includePending=true"
  fi

  request_json "GET" "$url"
  if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
  fi

  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
}

command_upload() {
  local entity_type=""
  local entity_id=""
  local file_path=""
  local content_type=""
  local checksum=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --entity-type) entity_type="$2"; shift 2 ;;
      --entity-id) entity_id="$2"; shift 2 ;;
      --file) file_path="$2"; shift 2 ;;
      --content-type) content_type="$2"; shift 2 ;;
      --checksum) checksum="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  require_entity "$entity_type" "$entity_id"
  if [[ -z "$file_path" ]]; then
    echo "Error: --file is required" >&2
    exit 1
  fi
  if [[ ! -f "$file_path" ]]; then
    echo "Error: file not found: $file_path" >&2
    exit 1
  fi

  local file_name
  file_name=$(basename "$file_path")
  local size_bytes
  size_bytes=$(wc -c < "$file_path" | tr -d ' ')

  if [[ -z "$content_type" ]]; then
    if command -v file >/dev/null 2>&1; then
      content_type=$(file --mime-type -b "$file_path")
    else
      content_type="application/octet-stream"
    fi
  fi

  local payload
  payload=$(jq -n \
    --arg entityType "$entity_type" \
    --arg entityId "$entity_id" \
    --arg fileName "$file_name" \
    --arg contentType "$content_type" \
    --argjson sizeBytes "$size_bytes" \
    --arg checksum "$checksum" \
    '{entityType:$entityType, entityId:$entityId, fileName:$fileName, contentType:$contentType, sizeBytes:$sizeBytes} + (if $checksum != "" then {checksumSha256:$checksum} else {} end)')

  echo "${ENV_PREFIX}Requesting upload URL..."
  request_json "POST" "${BASE_URL}/api/v1/atomicnebula/attachments/upload-url" "$payload"

  if is_approval_response "$HTTP_CODE" "$BODY"; then
    record_approval "upload" "$BODY"
    return
  fi
  if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
  fi

  local attachment_id
  attachment_id=$(echo "$BODY" | jq -r '.data.attachmentId')
  local confirm_token
  confirm_token=$(echo "$BODY" | jq -r '.data.confirmToken')
  local upload_url
  upload_url=$(echo "$BODY" | jq -r '.data.upload.sasUrl')

  if [[ -z "$attachment_id" || "$attachment_id" == "null" || -z "$upload_url" || "$upload_url" == "null" ]]; then
    echo "Error: upload-url response missing required fields" >&2
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
  fi

  local -a upload_headers
  upload_headers=()
  while IFS=$'\t' read -r key value; do
    [[ -z "$key" ]] && continue
    upload_headers+=("-H" "$key: $value")
  done < <(echo "$BODY" | jq -r '.data.upload.headers | to_entries[] | "\(.key)\t\(.value)"')

  echo "Uploading file bytes to SAS URL..."
  local upload_status
  upload_status=$(curl -s -o /tmp/an-attachment-upload-response.$$ -w "%{http_code}" -X PUT "${upload_headers[@]}" --data-binary "@$file_path" "$upload_url")
  rm -f /tmp/an-attachment-upload-response.$$ || true

  if [[ "$upload_status" -lt 200 || "$upload_status" -ge 300 ]]; then
    echo "Error: blob upload failed with status $upload_status" >&2
    exit 1
  fi

  local confirm_payload
  confirm_payload=$(jq -n \
    --arg entityType "$entity_type" \
    --arg entityId "$entity_id" \
    --arg confirmToken "$confirm_token" \
    '{entityType:$entityType, entityId:$entityId, confirmToken:$confirmToken}')

  echo "Confirming upload..."
  request_json "POST" "${BASE_URL}/api/v1/atomicnebula/attachments/${attachment_id}/confirm" "$confirm_payload"

  if is_approval_response "$HTTP_CODE" "$BODY"; then
    record_approval "upload-confirm" "$BODY"
    return
  fi
  if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
  fi

  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
}

command_download_url() {
  local attachment_id="$1"
  shift

  local entity_type=""
  local entity_id=""
  local disposition="attachment"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --entity-type) entity_type="$2"; shift 2 ;;
      --entity-id) entity_id="$2"; shift 2 ;;
      --disposition) disposition="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  require_entity "$entity_type" "$entity_id"
  local payload
  payload=$(jq -n \
    --arg entityType "$entity_type" \
    --arg entityId "$entity_id" \
    --arg disposition "$disposition" \
    '{entityType:$entityType, entityId:$entityId, disposition:$disposition}')

  request_json "POST" "${BASE_URL}/api/v1/atomicnebula/attachments/${attachment_id}/download-url" "$payload"
  if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
  fi

  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
}

command_link() {
  local attachment_id="$1"
  shift

  local entity_type=""
  local entity_id=""
  local relationship=""
  local order=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --entity-type) entity_type="$2"; shift 2 ;;
      --entity-id) entity_id="$2"; shift 2 ;;
      --relationship) relationship="$2"; shift 2 ;;
      --order) order="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  require_entity "$entity_type" "$entity_id"
  local payload
  payload=$(jq -n \
    --arg entityType "$entity_type" \
    --arg entityId "$entity_id" \
    --arg relationship "$relationship" \
    --arg order "$order" \
    '{entityType:$entityType, entityId:$entityId} + (if $relationship != "" then {relationship:$relationship} else {} end) + (if $order != "" then {displayOrder:($order|tonumber)} else {} end)')

  request_json "POST" "${BASE_URL}/api/v1/atomicnebula/attachments/${attachment_id}/link" "$payload"
  if is_approval_response "$HTTP_CODE" "$BODY"; then
    record_approval "link" "$BODY"
    return
  fi
  if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
  fi

  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
}

command_unlink() {
  local attachment_id="$1"
  shift

  local entity_type=""
  local entity_id=""
  local hard_delete_if_orphan=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --entity-type) entity_type="$2"; shift 2 ;;
      --entity-id) entity_id="$2"; shift 2 ;;
      --hard-delete-if-orphan) hard_delete_if_orphan="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  require_entity "$entity_type" "$entity_id"
  local payload
  payload=$(jq -n \
    --arg entityType "$entity_type" \
    --arg entityId "$entity_id" \
    --arg hardDelete "$hard_delete_if_orphan" \
    '{entityType:$entityType, entityId:$entityId} + (if $hardDelete != "" then {hardDeleteIfOrphan: ($hardDelete == "true")} else {} end)')

  request_json "DELETE" "${BASE_URL}/api/v1/atomicnebula/attachments/${attachment_id}/link" "$payload"
  if is_approval_response "$HTTP_CODE" "$BODY"; then
    record_approval "unlink" "$BODY"
    return
  fi
  if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
  fi

  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
}

CMD="$1"
shift || true

case "$CMD" in
  list)
    command_list "$@"
    ;;
  upload)
    command_upload "$@"
    ;;
  download-url)
    if [[ $# -lt 1 ]]; then
      echo "Error: attachmentId is required" >&2
      exit 1
    fi
    command_download_url "$@"
    ;;
  link)
    if [[ $# -lt 1 ]]; then
      echo "Error: attachmentId is required" >&2
      exit 1
    fi
    command_link "$@"
    ;;
  unlink)
    if [[ $# -lt 1 ]]; then
      echo "Error: attachmentId is required" >&2
      exit 1
    fi
    command_unlink "$@"
    ;;
  *)
    echo "Error: unknown command '$CMD'" >&2
    usage
    exit 1
    ;;
esac

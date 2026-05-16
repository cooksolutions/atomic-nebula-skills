#!/bin/bash
#
# Atomic Nebula CRM Meetings CLI Helper
#
# Manages an_meetings (CRM-significant records — typically AI recorder transcripts)
# and the open loops they produce. Distinct from the calendar events skill.
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
Atomic Nebula CRM Meetings CLI

Usage: an-meetings.sh [--env <workspace>] <command> [options]

Read commands:
  list                  List CRM meetings
  upcoming              Upcoming CRM meetings
  get <meetingId>       Get one meeting (transcript + vendor action items in metadata)
  loops list <meetingId>
                        List open loops derived from this meeting (alias: loops <meetingId>)

Write commands (require --confirm yes):
  create                Create a CRM meeting
  attach-transcript <meetingId>
                        Attach or replace the transcript on an existing meeting
  update <meetingId>    Update fields on a meeting
  cancel <meetingId>    Cancel (status -> cancelled)
  delete <meetingId>    Soft delete

Open loop verbs (require --confirm yes):
  loops promote <loopId>   Convert loop into a canonical task
  loops resolve <loopId>   Mark done without creating a task
  loops snooze <loopId> --until <iso|epochMs>
  loops dismiss <loopId>   Mark as false-positive / not relevant

List options:
  --status <s>             scheduled|in_progress|completed|cancelled
  --outcome <s>
  --contact-id <id>
  --company-id <id>
  --deal-id <id>
  --project-id <id>
  --lead-id <id>
  --owner-id <id>
  --start-after <iso>
  --start-before <iso>
  --search <term>
  --limit <n>              default 50
  --cursor <token>         nextCursor from the previous response

Create / update options:
  --subject <text>
  --start <iso>
  --end <iso>
  --transcript <text>
  --transcript-file <path>
  --location <text>
  --meeting-url <url>
  --outcome <s>            held|no_show|cancelled|rescheduled
  --calendar-event-id <id>
  --contact-id <id>
  --company-id <id>
  --deal-id <id>
  --project-id <id>
  --lead-id <id>
  --owner-id <id>
  --priority <s>
  --status <s>
  --tag <value>            (repeatable)
  --confirm yes
USAGE
}

require_api_key() {
  if [[ -z "${API_KEY:-}" ]]; then
    echo "Error: No API key found for workspace '${AN_ENV}'." >&2
    echo "Set ATOMICNEBULA_API_KEY or configure ${AN_ASSISTANT_CONFIG_FILE}." >&2
    exit 1
  fi
}

require_confirm() {
  local confirm="$1"
  if [[ "$confirm" != "yes" ]]; then
    echo "Error: write command requires --confirm yes" >&2
    exit 1
  fi
}

append_query_param() {
  local query="$1"
  local key="$2"
  local value="$3"
  if [[ -z "$value" ]]; then
    echo "$query"
    return
  fi
  local encoded
  encoded=$(printf '%s' "$value" | jq -sRr @uri)
  if [[ -z "$query" ]]; then
    echo "?${key}=${encoded}"
  else
    echo "${query}&${key}=${encoded}"
  fi
}

# ----- Meeting field parsing ---------------------------------------------

parse_meeting_fields() {
  SUBJECT=""
  START=""
  END=""
  TRANSCRIPT=""
  TRANSCRIPT_FILE=""
  LOCATION=""
  MEETING_URL=""
  OUTCOME=""
  CALENDAR_EVENT_ID=""
  CONTACT_ID=""
  COMPANY_ID=""
  DEAL_ID=""
  PROJECT_ID=""
  LEAD_ID=""
  OWNER_ID=""
  PRIORITY=""
  STATUS_FIELD=""
  TAGS=()
  CONFIRM=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --subject) SUBJECT="$2"; shift 2 ;;
      --start) START="$2"; shift 2 ;;
      --end) END="$2"; shift 2 ;;
      --transcript) TRANSCRIPT="$2"; shift 2 ;;
      --transcript-file) TRANSCRIPT_FILE="$2"; shift 2 ;;
      --location) LOCATION="$2"; shift 2 ;;
      --meeting-url) MEETING_URL="$2"; shift 2 ;;
      --outcome) OUTCOME="$2"; shift 2 ;;
      --calendar-event-id) CALENDAR_EVENT_ID="$2"; shift 2 ;;
      --contact-id) CONTACT_ID="$2"; shift 2 ;;
      --company-id) COMPANY_ID="$2"; shift 2 ;;
      --deal-id) DEAL_ID="$2"; shift 2 ;;
      --project-id) PROJECT_ID="$2"; shift 2 ;;
      --lead-id) LEAD_ID="$2"; shift 2 ;;
      --owner-id) OWNER_ID="$2"; shift 2 ;;
      --priority) PRIORITY="$2"; shift 2 ;;
      --status) STATUS_FIELD="$2"; shift 2 ;;
      --tag) TAGS+=("$2"); shift 2 ;;
      --confirm) CONFIRM="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -n "${TRANSCRIPT_FILE}" ]]; then
    if [[ ! -f "${TRANSCRIPT_FILE}" ]]; then
      echo "Error: transcript file not found: ${TRANSCRIPT_FILE}" >&2
      exit 1
    fi
    TRANSCRIPT="$(cat "${TRANSCRIPT_FILE}")"
  fi
}

meeting_json_body() {
  local include_source="$1"
  local tags_json="[]"
  if [[ ${#TAGS[@]} -gt 0 ]]; then
    tags_json=$(printf '%s\n' "${TAGS[@]}" | jq -R . | jq -s .)
  fi
  local source_value="luna"
  jq -n \
    --arg subject "${SUBJECT:-}" \
    --arg start "${START:-}" \
    --arg end "${END:-}" \
    --arg body "${TRANSCRIPT:-}" \
    --arg location "${LOCATION:-}" \
    --arg meetingUrl "${MEETING_URL:-}" \
    --arg outcome "${OUTCOME:-}" \
    --arg calendarEventId "${CALENDAR_EVENT_ID:-}" \
    --arg contactId "${CONTACT_ID:-}" \
    --arg companyId "${COMPANY_ID:-}" \
    --arg dealId "${DEAL_ID:-}" \
    --arg projectId "${PROJECT_ID:-}" \
    --arg leadId "${LEAD_ID:-}" \
    --arg ownerId "${OWNER_ID:-}" \
    --arg priority "${PRIORITY:-}" \
    --arg status "${STATUS_FIELD:-}" \
    --argjson tags "$tags_json" \
    --arg includeSource "${include_source}" \
    --arg source "${source_value}" \
    '{
      subject: (if $subject == "" then null else $subject end),
      startTime: (if $start == "" then null else $start end),
      endTime: (if $end == "" then null else $end end),
      body: (if $body == "" then null else $body end),
      location: (if $location == "" then null else $location end),
      meetingUrl: (if $meetingUrl == "" then null else $meetingUrl end),
      outcome: (if $outcome == "" then null else $outcome end),
      calendarEventId: (if $calendarEventId == "" then null else $calendarEventId end),
      contactId: (if $contactId == "" then null else $contactId end),
      companyId: (if $companyId == "" then null else $companyId end),
      dealId: (if $dealId == "" then null else $dealId end),
      projectId: (if $projectId == "" then null else $projectId end),
      leadId: (if $leadId == "" then null else $leadId end),
      ownerId: (if $ownerId == "" then null else $ownerId end),
      priority: (if $priority == "" then null else $priority end),
      status: (if $status == "" then null else $status end),
      tags: (if ($tags | length) == 0 then null else $tags end),
      source: (if $includeSource == "1" then $source else null end)
    } | with_entries(select(.value != null))'
}

# ----- Read commands ------------------------------------------------------

list_meetings() {
  local query=""
  local status="" outcome="" contact="" company="" deal="" project="" lead="" owner=""
  local start_after="" start_before="" search="" limit="50" cursor=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status) status="$2"; shift 2 ;;
      --outcome) outcome="$2"; shift 2 ;;
      --contact-id) contact="$2"; shift 2 ;;
      --company-id) company="$2"; shift 2 ;;
      --deal-id) deal="$2"; shift 2 ;;
      --project-id) project="$2"; shift 2 ;;
      --lead-id) lead="$2"; shift 2 ;;
      --owner-id) owner="$2"; shift 2 ;;
      --start-after) start_after="$2"; shift 2 ;;
      --start-before) start_before="$2"; shift 2 ;;
      --search) search="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      --cursor) cursor="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  query=$(append_query_param "$query" "status" "$status")
  query=$(append_query_param "$query" "outcome" "$outcome")
  query=$(append_query_param "$query" "contactId" "$contact")
  query=$(append_query_param "$query" "companyId" "$company")
  query=$(append_query_param "$query" "dealId" "$deal")
  query=$(append_query_param "$query" "projectId" "$project")
  query=$(append_query_param "$query" "leadId" "$lead")
  query=$(append_query_param "$query" "ownerId" "$owner")
  query=$(append_query_param "$query" "startAfter" "$start_after")
  query=$(append_query_param "$query" "startBefore" "$start_before")
  query=$(append_query_param "$query" "searchTerm" "$search")
  query=$(append_query_param "$query" "limit" "$limit")
  query=$(append_query_param "$query" "cursor" "$cursor")

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Listing CRM meetings from ${BASE_URL}" >&2
  curl "${CURL_BASE[@]}" "${BASE_URL}/api/v1/atomicnebula/meetings${query}" | jq .
}

upcoming_meetings() {
  local limit="10" owner=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      --owner-id) owner="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
  local query=""
  query=$(append_query_param "$query" "limit" "$limit")
  query=$(append_query_param "$query" "ownerId" "$owner")
  curl "${CURL_BASE[@]}" "${BASE_URL}/api/v1/atomicnebula/meetings/upcoming${query}" | jq .
}

get_meeting() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then echo "Error: meeting ID is required" >&2; exit 1; fi
  curl "${CURL_BASE[@]}" "${BASE_URL}/api/v1/atomicnebula/meetings/${id}" | jq .
}

list_loops_for_meeting() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then echo "Error: meeting ID is required" >&2; exit 1; fi
  curl "${CURL_BASE[@]}" "${BASE_URL}/api/v1/atomicnebula/meetings/${id}/loops" | jq .
}

# ----- Write commands -----------------------------------------------------

create_meeting() {
  parse_meeting_fields "$@"
  require_confirm "$CONFIRM"
  if [[ -z "${SUBJECT}" ]]; then echo "Error: --subject is required" >&2; exit 1; fi
  if [[ -z "${START}" ]]; then echo "Error: --start is required" >&2; exit 1; fi
  meeting_json_body 1 | curl "${CURL_BASE[@]}" -X POST --data @- "${BASE_URL}/api/v1/atomicnebula/meetings" | jq .
}

attach_transcript_meeting() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then echo "Error: meeting ID is required" >&2; exit 1; fi
  shift
  parse_meeting_fields "$@"
  require_confirm "$CONFIRM"
  if [[ -z "${TRANSCRIPT}" ]]; then echo "Error: --transcript or --transcript-file is required" >&2; exit 1; fi
  jq -n --arg body "${TRANSCRIPT}" '{ body: $body }' | curl "${CURL_BASE[@]}" -X PATCH --data @- "${BASE_URL}/api/v1/atomicnebula/meetings/${id}" | jq .
}

update_meeting() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then echo "Error: meeting ID is required" >&2; exit 1; fi
  shift
  parse_meeting_fields "$@"
  require_confirm "$CONFIRM"
  meeting_json_body 0 | curl "${CURL_BASE[@]}" -X PATCH --data @- "${BASE_URL}/api/v1/atomicnebula/meetings/${id}" | jq .
}

cancel_meeting() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then echo "Error: meeting ID is required" >&2; exit 1; fi
  shift
  local reason="" confirm=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      --confirm) confirm="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
  require_confirm "$confirm"
  jq -n --arg reason "$reason" '{ reason: (if $reason == "" then null else $reason end) } | with_entries(select(.value != null))' \
    | curl "${CURL_BASE[@]}" -X POST --data @- "${BASE_URL}/api/v1/atomicnebula/meetings/${id}/cancel" | jq .
}

delete_meeting() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then echo "Error: meeting ID is required" >&2; exit 1; fi
  shift
  local confirm=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --confirm) confirm="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
  require_confirm "$confirm"
  curl "${CURL_BASE[@]}" -X DELETE "${BASE_URL}/api/v1/atomicnebula/meetings/${id}"
}

# ----- Open loop verbs ----------------------------------------------------

loop_promote() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then echo "Error: loop ID is required" >&2; exit 1; fi
  shift
  local title="" due_date="" priority="" category="" project_id="" assignee="" confirm=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --due-date) due_date="$2"; shift 2 ;;
      --priority) priority="$2"; shift 2 ;;
      --category) category="$2"; shift 2 ;;
      --project-id) project_id="$2"; shift 2 ;;
      --assignee-user-id) assignee="$2"; shift 2 ;;
      --confirm) confirm="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
  require_confirm "$confirm"
  jq -n \
    --arg title "$title" \
    --arg dueDate "$due_date" \
    --arg priority "$priority" \
    --arg category "$category" \
    --arg projectId "$project_id" \
    --arg assigneeUserId "$assignee" \
    '{
      title: (if $title == "" then null else $title end),
      dueDate: (if $dueDate == "" then null else $dueDate end),
      priority: (if $priority == "" then null else $priority end),
      category: (if $category == "" then null else $category end),
      projectId: (if $projectId == "" then null else $projectId end),
      assigneeUserId: (if $assigneeUserId == "" then null else $assigneeUserId end)
    } | with_entries(select(.value != null))' \
    | curl "${CURL_BASE[@]}" -X POST --data @- "${BASE_URL}/api/v1/atomicnebula/openloops/${id}/promote" | jq .
}

loop_resolve() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then echo "Error: loop ID is required" >&2; exit 1; fi
  shift
  local reason="" confirm=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      --confirm) confirm="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
  require_confirm "$confirm"
  jq -n --arg reason "$reason" '{ reason: (if $reason == "" then null else $reason end) } | with_entries(select(.value != null))' \
    | curl "${CURL_BASE[@]}" -X POST --data @- "${BASE_URL}/api/v1/atomicnebula/openloops/${id}/resolve" | jq .
}

loop_snooze() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then echo "Error: loop ID is required" >&2; exit 1; fi
  shift
  local until="" confirm=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --until) until="$2"; shift 2 ;;
      --confirm) confirm="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
  require_confirm "$confirm"
  if [[ -z "$until" ]]; then echo "Error: --until <iso|epochMs> is required" >&2; exit 1; fi
  jq -n --arg until "$until" \
    '{ until: (if ($until | test("^[0-9]+$")) then ($until | tonumber) else $until end) }' \
    | curl "${CURL_BASE[@]}" -X POST --data @- "${BASE_URL}/api/v1/atomicnebula/openloops/${id}/snooze" | jq .
}

loop_dismiss() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then echo "Error: loop ID is required" >&2; exit 1; fi
  shift
  local confirm=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --confirm) confirm="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
  require_confirm "$confirm"
  curl "${CURL_BASE[@]}" -X POST -d '{}' "${BASE_URL}/api/v1/atomicnebula/openloops/${id}/dismiss" | jq .
}

dispatch_loops() {
  local sub="${1:-}"
  if [[ -z "$sub" ]]; then
    echo "Error: missing loops subcommand. Try: loops list <meetingId> | loops promote|resolve|snooze|dismiss <loopId>" >&2
    exit 1
  fi
  shift
  case "$sub" in
    list)
      local meeting_id="${1:-}"
      if [[ -z "$meeting_id" ]]; then
        echo "Error: loops list requires a <meetingId>" >&2
        exit 1
      fi
      list_loops_for_meeting "$meeting_id"
      ;;
    promote) loop_promote "$@" ;;
    resolve) loop_resolve "$@" ;;
    snooze) loop_snooze "$@" ;;
    dismiss) loop_dismiss "$@" ;;
    *)
      # Backwards-compatible: bare `loops <meetingId>` still lists for that meeting.
      list_loops_for_meeting "$sub"
      ;;
  esac
}

# ----- Dispatcher ---------------------------------------------------------

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" || -z "${1:-}" ]]; then
  usage
  exit 0
fi

require_api_key

case "${1:-}" in
  list) shift; list_meetings "$@" ;;
  upcoming) shift; upcoming_meetings "$@" ;;
  get) shift; get_meeting "$@" ;;
  loops) shift; dispatch_loops "$@" ;;
  create) shift; create_meeting "$@" ;;
  attach-transcript) shift; attach_transcript_meeting "$@" ;;
  update) shift; update_meeting "$@" ;;
  cancel) shift; cancel_meeting "$@" ;;
  delete) shift; delete_meeting "$@" ;;
  *) echo "Error: unknown command '$1'" >&2; usage; exit 1 ;;
esac

#!/bin/bash
#
# Atomic Nebula Calendar CLI Helper
#
# A convenience script for querying Atomic Nebula meetings, events, and availability.
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

RUN_ID=$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "run-$(date +%s)-$$")
WRITE_RUNS_LOG="${HOME}/.openclaw/logs/write-runs.log"

# Handle help early before requiring API key
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "help" ]]; then
  cat << 'USAGE'
Atomic Nebula Calendar CLI

Usage: an-calendar.sh [--env <workspace>] <command> [options]

Commands:
  list              List CRM meetings with optional filters
  events            List calendar events from provider (Exchange/Google)
  targets           List accessible calendar mailboxes and calendars
  create            Create a provider-backed calendar event
  update <eventId>  Update a provider-backed calendar event
  delete <eventId>  Delete a provider-backed calendar event
  today             Shortcut for `events --today`
  upcoming          Get upcoming events (calendar + CRM meetings combined)
  get <meetingId>   Get full CRM meeting details
  availability      Find free time slots for a date

Global Options:
  --env <env>           Target workspace slug (e.g., spider, dev, circeaurasupport)

List Options:
  --status <value>      Filter by status (scheduled, completed, cancelled)
  --outcome <value>     Filter by outcome
  --contact <id>        Filter by contact ID
  --company <id>        Filter by company ID
  --deal <id>           Filter by deal ID
  --project <id>        Filter by project ID
  --lead <id>           Filter by lead ID
  --owner <id>          Filter by owner ID
  --start-after <date>  Meetings starting after this date (ISO format)
  --start-before <date> Meetings starting before this date (ISO format)
  --search <term>       Search in title/description
  --today               Shortcut for today's date range
  --week                Shortcut for this week's date range
  --limit <n>           Max results (default: 50)
  --cursor <token>      nextCursor from the previous response

Events Options:
  --today               Today's events
  --date <date>         Specific date (YYYY-MM-DD)
  --start <datetime>    Start of range (ISO format)
  --end <datetime>      End of range (ISO format)
  --resource-ids <ids>  Comma-separated resource IDs to scope event listing
  --include-cancelled   Include cancelled events

Create/Update Options:
  --resource-id <id>    Calendar resource/mailbox ID
  --calendar-id <id>    Provider calendar ID
  --subject <text>      Event subject
  --start <datetime>    Start datetime (ISO format)
  --end <datetime>      End datetime (ISO format)
  --timezone <tz>       IANA timezone for provider write
  --body <text>         Body/description
  --location <text>     Location display name
  --attendee <email>    Required attendee (repeatable)
  --optional-attendee <email>
                        Optional attendee (repeatable)
  --all-day             Mark event as all-day
  --online              Request an online meeting when supported
  --send-updates        Send provider updates/cancellations using mode "all"
  --send-updates-mode   all | none | externalOnly

Availability Options:
  --date <date>         Find availability for this date (required)
  --duration <minutes>  Minimum free-slot duration (default: 30)
  --resource-ids <ids>  Comma-separated resource IDs to scope availability

Workspace Config:
  API keys resolve from env vars, assistant-workspaces.json, or legacy OpenClaw config.
  Fallback env vars:
    ATOMICNEBULA_API_KEY / ATOMICNEBULA_BASE_URL (production)
    ATOMICNEBULA_DEV_API_KEY / ATOMICNEBULA_DEV_BASE_URL (dev)

Examples:
  # Get upcoming events (calendar + CRM)
  an-calendar.sh upcoming

  # Today's calendar events from Exchange/Google
  an-calendar.sh events --today

  # List writable mailboxes/calendars
  an-calendar.sh targets

  # Create a calendar event using saved default target
  an-calendar.sh create --subject "Planning" --start 2026-04-22T09:00:00Z --end 2026-04-22T09:30:00Z

  # Update a calendar event
  an-calendar.sh update CAL-123 --location "Teams" --online

  # Delete a calendar event
  an-calendar.sh delete CAL-123 --send-updates

  # Shortcut for today's calendar events
  an-calendar.sh today

  # List CRM meetings on dev
  an-calendar.sh --env dev list --today

  # List meetings for a specific date range
  an-calendar.sh list --start-after 2026-02-20 --start-before 2026-02-27

  # Find free time slots today
  an-calendar.sh availability --date $(date +%Y-%m-%d)

  # Get meeting details
  an-calendar.sh get MEET-0042
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

api_request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"

  if [[ -n "$body" ]]; then
    curl "${CURL_OPTS[@]}" -X "$method" -d "$body" "${BASE_URL}${path}"
  else
    curl "${CURL_OPTS[@]}" -X "$method" "${BASE_URL}${path}"
  fi
}

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
  local -a headers=("${CURL_OPTS[@]}")

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

json_string_array_from_args() {
  if [[ $# -eq 0 ]]; then
    printf '[]'
    return
  fi
  printf '%s\n' "$@" | jq -R . | jq -s 'map(select(length > 0))'
}

build_query_string() {
  local query=""
  local first=1
  local today=""
  local week=""

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
      --status) add_param "status" "$2"; shift 2 ;;
      --outcome) add_param "outcome" "$2"; shift 2 ;;
      --contact) add_param "contactId" "$2"; shift 2 ;;
      --company) add_param "companyId" "$2"; shift 2 ;;
      --deal) add_param "dealId" "$2"; shift 2 ;;
      --project) add_param "projectId" "$2"; shift 2 ;;
      --lead) add_param "leadId" "$2"; shift 2 ;;
      --owner) add_param "ownerId" "$2"; shift 2 ;;
      --start-after) add_param "startAfter" "$2"; shift 2 ;;
      --start-before) add_param "startBefore" "$2"; shift 2 ;;
      --search) add_param "searchTerm" "$2"; shift 2 ;;
      --limit) add_param "limit" "$2"; shift 2 ;;
      --cursor) add_param "cursor" "$2"; shift 2 ;;
      --today) today="1"; shift ;;
      --week) week="1"; shift ;;
      *) shift ;;
    esac
  done

  # Handle --today shortcut
  if [[ -n "$today" ]]; then
    local today_date
    today_date=$(date +%Y-%m-%d)
    add_param "startAfter" "${today_date}T00:00:00Z"
    add_param "startBefore" "${today_date}T23:59:59Z"
  fi

  # Handle --week shortcut
  if [[ -n "$week" ]]; then
    local week_start week_end
    week_start=$(date +%Y-%m-%d)
    week_end=$(date -v+7d +%Y-%m-%d 2>/dev/null || date -d "+7 days" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
    add_param "startAfter" "${week_start}T00:00:00Z"
    add_param "startBefore" "${week_end}T23:59:59Z"
  fi

  echo "$query"
}

list_meetings() {
  local query
  query=$(build_query_string "$@")
  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Listing meetings from ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" "${BASE_URL}/api/v1/atomicnebula/meetings${query}" | jq .
}

list_events() {
  local start_dt="" end_dt="" include_cancelled="" resource_ids=""
  local use_today="" use_date=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --today) use_today="1"; shift ;;
      --date) use_date="$2"; shift 2 ;;
      --start) start_dt="$2"; shift 2 ;;
      --end) end_dt="$2"; shift 2 ;;
      --include-cancelled) include_cancelled="true"; shift ;;
      --resource-ids) resource_ids="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -n "$use_today" ]]; then
    local today_date
    today_date=$(date +%Y-%m-%d)
    start_dt="${today_date}T00:00:00Z"
    end_dt="${today_date}T23:59:59Z"
  elif [[ -n "$use_date" ]]; then
    start_dt="${use_date}T00:00:00Z"
    end_dt="${use_date}T23:59:59Z"
  elif [[ -z "$start_dt" ]]; then
    # Default to today
    local today_date
    today_date=$(date +%Y-%m-%d)
    start_dt="${today_date}T00:00:00Z"
    end_dt="${today_date}T23:59:59Z"
  fi

  local query="?startDateTime=$(printf '%s' "$start_dt" | jq -sRr @uri)"
  if [[ -n "$end_dt" ]]; then
    query+="&endDateTime=$(printf '%s' "$end_dt" | jq -sRr @uri)"
  fi
  if [[ -n "$include_cancelled" ]]; then
    query+="&includeCancelled=true"
  fi
  if [[ -n "$resource_ids" ]]; then
    query+="&resourceIds=$(printf '%s' "$resource_ids" | jq -sRr @uri)"
  fi

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Calendar events from ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" "${BASE_URL}/api/v1/atomicnebula/calendar/events${query}" | jq '{
    success: .success,
    count: (.data.items | length),
    events: [.data.items[] | {
      id: .id,
      subject: (.subject // "(No subject)"),
      resourceId: .resourceId,
      calendarId: .calendarId,
      start: (.startDateTime / 1000 | strftime("%H:%M")),
      end: (.endDateTime / 1000 | strftime("%H:%M")),
      allDay: .isAllDay,
      cancelled: .isCancelled,
      online: .isOnlineMeeting,
      joinUrl: .onlineMeetingJoinUrl,
      attendees: [(.attendees // [])[] | "\(.name) <\(.email)>"],
      provider: .provider
    }]
  }'
}

list_targets() {
  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Listing calendar targets from ${BASE_URL}" >&2
  api_request GET "/api/v1/atomicnebula/calendar/targets" | jq .
}

build_calendar_write_payload() {
  local subject="${1:-}"
  local start_dt="${2:-}"
  local end_dt="${3:-}"
  shift 3 || true

  local resource_id=""
  local calendar_id=""
  local timezone=""
  local body=""
  local location=""
  local is_all_day="false"
  local create_online_meeting="false"
  local send_updates=""
  local -a required_attendees=()
  local -a optional_attendees=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --resource-id) resource_id="$2"; shift 2 ;;
      --calendar-id) calendar_id="$2"; shift 2 ;;
      --subject) subject="$2"; shift 2 ;;
      --start) start_dt="$2"; shift 2 ;;
      --end) end_dt="$2"; shift 2 ;;
      --timezone) timezone="$2"; shift 2 ;;
      --body) body="$2"; shift 2 ;;
      --location) location="$2"; shift 2 ;;
      --attendee) required_attendees+=("$2"); shift 2 ;;
      --optional-attendee) optional_attendees+=("$2"); shift 2 ;;
      --all-day) is_all_day="true"; shift ;;
      --online) create_online_meeting="true"; shift ;;
      --send-updates) send_updates="all"; shift ;;
      --send-updates-mode) send_updates="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -n "$send_updates" ]] && [[ "$send_updates" != "all" && "$send_updates" != "none" && "$send_updates" != "externalOnly" ]]; then
    echo "Error: --send-updates-mode must be one of: all, none, externalOnly" >&2
    exit 1
  fi

  local required_attendees_json optional_attendees_json
  required_attendees_json=$(json_string_array_from_args "${required_attendees[@]-}")
  optional_attendees_json=$(json_string_array_from_args "${optional_attendees[@]-}")

  jq -n \
    --arg resourceId "$resource_id" \
    --arg calendarId "$calendar_id" \
    --arg subject "$subject" \
    --arg startDateTime "$start_dt" \
    --arg endDateTime "$end_dt" \
    --arg timeZone "$timezone" \
    --arg body "$body" \
    --arg location "$location" \
    --argjson isAllDay "$is_all_day" \
    --argjson createOnlineMeeting "$create_online_meeting" \
    --arg sendUpdates "$send_updates" \
    --argjson requiredAttendees "$required_attendees_json" \
    --argjson optionalAttendees "$optional_attendees_json" \
    '{
      subject: $subject,
      startDateTime: $startDateTime,
      endDateTime: $endDateTime
    }
    + (if ($resourceId | length) > 0 then {resourceId: $resourceId} else {} end)
    + (if ($calendarId | length) > 0 then {calendarId: $calendarId} else {} end)
    + (if ($timeZone | length) > 0 then {timeZone: $timeZone} else {} end)
    + (if ($body | length) > 0 then {body: $body} else {} end)
    + (if ($location | length) > 0 then {location: $location} else {} end)
    + (if $isAllDay then {isAllDay: true} else {} end)
    + (if $createOnlineMeeting then {createOnlineMeeting: true} else {} end)
    + (if ($sendUpdates | length) > 0 then {sendUpdates: $sendUpdates} else {} end)
    + (if (($requiredAttendees | length) + ($optionalAttendees | length)) > 0
        then {attendees: (($requiredAttendees | map({email: .})) + ($optionalAttendees | map({email: ., optional: true})))}
        else {}
      end)'
}

create_event() {
  local payload
  payload=$(build_calendar_write_payload "" "" "" "$@")

  if [[ "$(printf '%s' "$payload" | jq -r '.subject // ""')" == "" ]]; then
    echo "Error: --subject is required" >&2
    exit 1
  fi
  if [[ "$(printf '%s' "$payload" | jq -r '.startDateTime // ""')" == "" ]]; then
    echo "Error: --start is required" >&2
    exit 1
  fi
  if [[ "$(printf '%s' "$payload" | jq -r '.endDateTime // ""')" == "" ]]; then
    echo "Error: --end is required" >&2
    exit 1
  fi

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Creating calendar event via ${BASE_URL}" >&2
  request_json POST "/api/v1/atomicnebula/calendar/events" "$payload" "true"
  print_or_fail "calendar.create"
}

update_event() {
  local event_id="${1:-}"
  shift || true

  if [[ -z "$event_id" ]]; then
    echo "Error: eventId is required" >&2
    exit 1
  fi

  local payload
  payload=$(build_calendar_write_payload "" "" "" "$@")

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Updating calendar event ${event_id} via ${BASE_URL}" >&2
  request_json PATCH "/api/v1/atomicnebula/calendar/events/${event_id}" "$payload" "true"
  print_or_fail "calendar.update"
}

delete_event() {
  local event_id="${1:-}"
  shift || true
  local send_updates=""

  if [[ -z "$event_id" ]]; then
    echo "Error: eventId is required" >&2
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --send-updates) send_updates="all"; shift ;;
      --send-updates-mode) send_updates="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  local payload
  if [[ -n "$send_updates" ]] && [[ "$send_updates" != "all" && "$send_updates" != "none" && "$send_updates" != "externalOnly" ]]; then
    echo "Error: --send-updates-mode must be one of: all, none, externalOnly" >&2
    exit 1
  fi

  payload=$(jq -n --arg sendUpdates "$send_updates" 'if ($sendUpdates | length) > 0 then {sendUpdates: $sendUpdates} else {} end')

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Deleting calendar event ${event_id} via ${BASE_URL}" >&2
  request_json DELETE "/api/v1/atomicnebula/calendar/events/${event_id}" "$payload" "true"
  print_or_fail "calendar.delete"
}

get_upcoming() {
  local limit="10"
  local owner=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      --owner) owner="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  # Get calendar events from now until end of day
  local now_iso end_iso
  now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  end_iso=$(date -u +%Y-%m-%dT23:59:59Z)

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Getting upcoming events from ${BASE_URL}" >&2

  local events_json
  events_json=$(curl "${CURL_OPTS[@]}" "${BASE_URL}/api/v1/atomicnebula/calendar/events?startDateTime=$(printf '%s' "$now_iso" | jq -sRr @uri)&endDateTime=$(printf '%s' "$end_iso" | jq -sRr @uri)" 2>/dev/null || echo '{"data":{"items":[]}}')

  local meetings_query="?limit=${limit}"
  if [[ -n "$owner" ]]; then
    meetings_query+="&ownerId=$(printf '%s' "$owner" | jq -sRr @uri)"
  fi
  local meetings_json
  meetings_json=$(curl "${CURL_OPTS[@]}" "${BASE_URL}/api/v1/atomicnebula/meetings/upcoming${meetings_query}" 2>/dev/null || echo '{"data":[]}')

  # Merge calendar events and CRM meetings into a unified view
  jq -n \
    --argjson events "$events_json" \
    --argjson meetings "$meetings_json" \
    '{
      calendarEvents: [($events.data.items // [])[] | select(.isCancelled != true) | {
        type: "calendar",
        id: .id,
        subject: (.subject // "(No subject)"),
        start: (.startDateTime / 1000 | strftime("%H:%M")),
        end: (.endDateTime / 1000 | strftime("%H:%M")),
        online: .isOnlineMeeting,
        joinUrl: .onlineMeetingJoinUrl,
        provider: .provider
      }],
      crmMeetings: [($meetings.data // [])[] | {
        type: "crm",
        subject: .subject,
        startTime: .startTime,
        status: .status,
        meetingUrl: .meetingUrl
      }]
    }'
}

get_meeting() {
  local meeting_id="${1:-}"
  if [[ -z "$meeting_id" ]]; then
    echo "Error: meetingId is required" >&2
    exit 1
  fi
  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Getting meeting ${meeting_id} from ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" "${BASE_URL}/api/v1/atomicnebula/meetings/${meeting_id}" | jq .
}

calculate_availability() {
  local date=""
  local duration="30"
  local resource_ids=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --date) date="$2"; shift 2 ;;
      --duration) duration="$2"; shift 2 ;;
      --resource-ids) resource_ids="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$date" ]]; then
    echo "Error: --date is required for availability" >&2
    exit 1
  fi

  local query="?date=${date}&durationMinutes=${duration}"
  if [[ -n "$resource_ids" ]]; then
    query+="&resourceIds=$(printf '%s' "$resource_ids" | jq -sRr @uri)"
  fi

  [[ -n "$ENV_PREFIX" ]] && echo "${ENV_PREFIX}Checking availability from ${BASE_URL}" >&2
  curl "${CURL_OPTS[@]}" "${BASE_URL}/api/v1/atomicnebula/calendar/availability${query}" | jq .
}

# Main command parser
case "${1:-}" in
  list)
    shift
    list_meetings "$@"
    ;;
  events)
    shift
    list_events "$@"
    ;;
  targets)
    shift
    list_targets "$@"
    ;;
  create)
    shift
    create_event "$@"
    ;;
  update)
    shift
    update_event "$@"
    ;;
  delete)
    shift
    delete_event "$@"
    ;;
  today)
    shift
    list_events --today "$@"
    ;;
  upcoming)
    shift
    get_upcoming "$@"
    ;;
  get)
    shift
    get_meeting "$@"
    ;;
  availability)
    shift
    calculate_availability "$@"
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

#!/bin/bash
#
# Atomic Nebula Digest CLI Helper
#
# A convenience script for getting workspace digests, briefings, and due items.
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
Atomic Nebula Digest CLI

Usage: an-digest.sh [--env <workspace>] <command> [options]

Commands:
  today              Get full daily digest (completed, pending, upcoming, strategic)
  briefing           Get concise briefing summary
  emails             List recent emails for briefing composition
  due                Get items due within a time window
  upcoming           Get upcoming horizon view
  notified           Mark reminder notification keys as delivered (dedupe)

Global Options:
  --env <workspace>  Target workspace slug (e.g., spider, dev, circeaurasupport)

Today Options:
  --date <YYYY-MM-DD>    Target date (default: today)
  --timezone <iana>      Override resolved user/workspace timezone
  --channels <list>      Filter channels: email,sms or "all" (default: all)
  --details              Include full item lists

Briefing Options:
  --timezone <iana>      Override resolved user/workspace timezone

Emails Options:
  --limit <n>            Number of emails to return (default: 5, max: 20)
  --mailbox <address>    Restrict to a mailbox address
  --search <term>        Search subject, sender, and preview
  --include-read         Include read mail (default: unread only)
  --importance <value>   Importance filter (default: normal)

Due Options:
  --within <minutes>     Time window (default: 15, max: 120)
  --types <list>         Item types: task,meeting,sla,reminder or "all" (default: all)
  --min-urgency <level>  Minimum urgency: now, soon, upcoming (default: soon)

Upcoming Options:
  --days <n>             Days to include (default: 5, max: 14)
  --timezone <iana>      Override resolved user/workspace timezone

Notified Options:
  --keys <csv>           Comma-separated notification keys (required)
  --channel <value>      Source channel label (default: openclaw)
  --expires-after <ms>   TTL in milliseconds (default backend: 86400000)
  --notified-at <ms>     Unix epoch milliseconds (default: now)

Workspace Config:
  API keys and base URLs are resolved from openclaw.json workspace config.
  Run 'an-env-list.sh' to see available workspaces.
  Fallback env vars (used when workspace not in config):
    ATOMICNEBULA_API_KEY / ATOMICNEBULA_BASE_URL (production)
    ATOMICNEBULA_DEV_API_KEY / ATOMICNEBULA_DEV_BASE_URL (dev)
    ATOMICNEBULA_STAGING_API_KEY / ATOMICNEBULA_STAGING_BASE_URL (staging)

Examples:
  # Full daily digest
  an-digest.sh today

  # Digest for a specific date
  an-digest.sh today --date 2024-01-15

  # Concise briefing
  an-digest.sh briefing

  # Top unread emails for briefing composition
  an-digest.sh emails --limit 5

  # Items due within 30 minutes
  an-digest.sh due --within 30

  # Only tasks and meetings due soon
  an-digest.sh due --types task,meeting --min-urgency soon

  # Upcoming horizon for next 7 days
  an-digest.sh upcoming --days 7

  # Mark keys as notified (dedupe)
  an-digest.sh notified --keys "task:abc,meeting:def" --channel openclaw

  # Dev workspace
  an-digest.sh --env dev briefing
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

# Show active workspace for non-production
ENV_PREFIX=$(print_env_prefix)

# Helper: Make API call with proper error handling
# Captures response and HTTP status, validates before returning JSON
api_call() {
  local url="$1"
  local response_with_status
  local http_code
  local response_body

  # Capture both response body and HTTP status code
  response_with_status=$(curl "${CURL_OPTS[@]}" -w '\n%{http_code}' "$url" 2>&1)
  http_code=$(echo "$response_with_status" | tail -n 1)
  response_body=$(echo "$response_with_status" | sed '$d')

  # Check for HTTP errors
  if [[ "$http_code" -lt 200 ]] || [[ "$http_code" -ge 300 ]]; then
    echo "Error: HTTP $http_code" >&2
    # Try to extract error message from response
    if [[ -n "$response_body" ]]; then
      echo "$response_body" | jq -r '.error.message // .error // "Unknown error"' >&2 2>/dev/null || echo "$response_body" >&2
    fi
    return 1
  fi

  # Validate JSON before returning
  if ! echo "$response_body" | jq empty 2>/dev/null; then
    echo "Error: Invalid JSON response" >&2
    echo "$response_body" >&2
    return 1
  fi

  echo "$response_body"
}

# Helper: POST API call with JSON payload and shared error handling
api_call_post() {
  local url="$1"
  local payload="$2"
  local response_with_status
  local http_code
  local response_body

  response_with_status=$(curl "${CURL_OPTS[@]}" -X POST -d "$payload" -w '\n%{http_code}' "$url" 2>&1)
  http_code=$(echo "$response_with_status" | tail -n 1)
  response_body=$(echo "$response_with_status" | sed '$d')

  if [[ "$http_code" -lt 200 ]] || [[ "$http_code" -ge 300 ]]; then
    echo "Error: HTTP $http_code" >&2
    if [[ -n "$response_body" ]]; then
      echo "$response_body" | jq -r '.error.message // .error // "Unknown error"' >&2 2>/dev/null || echo "$response_body" >&2
    fi
    return 1
  fi

  if ! echo "$response_body" | jq empty 2>/dev/null; then
    echo "Error: Invalid JSON response" >&2
    echo "$response_body" >&2
    return 1
  fi

  echo "$response_body"
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

  # Parse options (generic)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --within) add_param "withinMinutes" "$2"; shift 2 ;;
      --types) add_param "includeTypes" "$2"; shift 2 ;;
      --min-urgency) add_param "minUrgency" "$2"; shift 2 ;;
      --days) add_param "daysAhead" "$2"; shift 2 ;;
      --date) add_param "date" "$2"; shift 2 ;;
      --timezone) add_param "timezone" "$2"; shift 2 ;;
      --channels) add_param "channels" "$2"; shift 2 ;;
      --details) add_param "includeDetails" "true"; shift ;;
      --env) shift 2 ;; # Already handled by extract_env_flag
      --*)
        echo "Warning: Unrecognized option '$1'" >&2
        shift
        ;;
      *) shift ;;
    esac
  done

  echo "$query"
}

get_today() {
  local query
  query=$(build_query_string "$@")

  echo "${ENV_PREFIX}📰 Daily Digest"
  echo ""

  local response
  response=$(api_call "${BASE_URL}/api/v1/atomicnebula/digest${query}") || return 1

  echo "$response" | jq '{
    date: .data.meta.date,
    timezone: {
      name: .data.meta.timezone,
      source: .data.meta.timezoneSource,
      localTime: .data.meta.localTime,
      note: .data.meta.temporalContext
    },
    completed: .data.completed.summary,
    pending: {
      critical: .data.pending.byUrgency.critical | length,
      high: .data.pending.byUrgency.high | length,
      medium: .data.pending.byUrgency.medium | length,
      low: .data.pending.byUrgency.low | length
    },
    upcoming: {
      today: .data.upcoming.horizon[0] | {
        tasks: (.items.tasks | length),
        meetings: (.items.meetings | length),
        flagged: .flagged,
        flagReasons: .flagReasons
      }
    },
    strategic: {
      activeProjects: .data.strategic.activeProjects | length,
      weekFocus: .data.strategic.weekOverview.focusAreas
    }
  }'
}

get_briefing() {
  local query
  query=$(build_query_string --details --days 1 "$@")

  echo "${ENV_PREFIX}📰 Briefing"
  echo ""

  # Get condensed digest with details for top items
  local digest_json
  digest_json=$(api_call "${BASE_URL}/api/v1/atomicnebula/digest${query}") || return 1

  # Parse and format briefing
  echo "$digest_json" | jq -r '
    def format_local_time:
      if .startsAtLocal then (.startsAtLocal | split("T")[1] | .[0:5])
      elif .startsAt == null then ""
      else (.startsAt / 1000 | strftime("%H:%M"))
      end;

    "Date: \(.data.meta.date)",
    "Timezone: \(.data.meta.timezone) (\(.data.meta.timezoneSource)); local time \(.data.meta.localTime)",
    "Time context: \(.data.meta.temporalContext)",
    "",
    "=== Completed ===",
    "Tasks: \(.data.completed.summary.tasksCompleted)  Meetings: \(.data.completed.summary.meetingsHeld)  Messages: \(.data.completed.summary.messagesReceived)",
    "",
    "=== Top Priority ===",
    (.data.pending.attention.items[:5][] | "  [\(.urgency)] \(.title)"),
    "",
    "=== Today ===",
    (.data.upcoming.horizon[0] | (
      if .items.meetings | length > 0 then
        "Meetings:",
        (.items.meetings[] | "  \(. | format_local_time) - \(.title)")
      else empty end,
      if .items.tasks | length > 0 then
        "Tasks due:",
        (.items.tasks[] | "  [\(.priority)] \(.title)")
      else empty end,
      if .flagged then
        "",
        "⚠️  Flagged: \(.flagReasons | join(", "))"
      else empty end
    )),
    "",
    "=== Active Projects: \(.data.strategic.activeProjects | length) ===",
    (.data.strategic.activeProjects[:3][] | "  - \(.name) (\(.progress)%)")
  '
}

get_emails() {
  local limit="5"
  local mailbox=""
  local search=""
  local include_read="false"
  local importance=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit)
        limit="${2:-5}"
        shift 2
        ;;
      --mailbox)
        mailbox="${2:-}"
        shift 2
        ;;
      --search)
        search="${2:-}"
        shift 2
        ;;
      --include-read)
        include_read="true"
        shift
        ;;
      --importance)
        importance="${2:-}"
        shift 2
        ;;
      --env)
        shift 2
        ;;
      --*)
        echo "Error: Unrecognized option '$1' for emails command" >&2
        return 1
        ;;
      *)
        shift
        ;;
    esac
  done

  if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
    echo "Error: --limit must be a positive integer" >&2
    return 1
  fi
  if (( limit < 1 || limit > 20 )); then
    echo "Error: --limit must be between 1 and 20" >&2
    return 1
  fi

  local query="?limit=${limit}"
  if [[ "$include_read" != "true" ]]; then
    query+="&isRead=false"
  fi
  if [[ -n "$mailbox" ]]; then
    query+="&mailboxAddress=$(printf '%s' "$mailbox" | jq -sRr @uri)"
  fi
  if [[ -n "$search" ]]; then
    query+="&search=$(printf '%s' "$search" | jq -sRr @uri)"
  fi
  if [[ -n "$importance" ]]; then
    query+="&importance=$(printf '%s' "$importance" | jq -sRr @uri)"
  fi

  echo "${ENV_PREFIX}📬 Emails"
  echo ""

  local response
  response=$(api_call "${BASE_URL}/api/v1/atomicnebula/emails${query}") || return 1

  echo "$response" | jq '{
    count: (.data.emails | length),
    emails: [.data.emails[] | {
      id,
      subject: (.subject // "(No subject)"),
      from: (.fromName // .from // "Unknown"),
      mailbox: (.mailboxAddress // null),
      importance,
      unread: (.isRead | not),
      receivedAt,
      received: ((.receivedAt / 1000) | strftime("%Y-%m-%d %H:%M")),
      actionHint: (
        if ((.subject // "" | ascii_downcase | test("security|quarantine|alert|verify|urgent|mfa|totp|invoice|payment|meeting|invite|invitation"))
          or (.from // "" | ascii_downcase | test("microsoft|security|quarantine|accounts|billing")))
        then "Open"
        elif (.subject // "" | ascii_downcase | startswith("re:"))
        then "Reply"
        else "Review"
        end
      ),
      preview: (.bodyPreview // "")
    }]
  }'
}

get_due() {
  local query
  query=$(build_query_string "$@")

  echo "${ENV_PREFIX}⏰ Due Items"
  echo ""

  local response
  response=$(api_call "${BASE_URL}/api/v1/atomicnebula/reminders/due${query}") || return 1

  echo "$response" | jq '{
    window: .data.query.withinMinutes,
    summary: .data.summary,
    items: [.data.items[] | {
      type,
      title,
      minutesUntil,
      urgency,
      notification: .notificationText
    }]
  }'
}

get_upcoming() {
  local query
  query=$(build_query_string "$@")

  echo "${ENV_PREFIX}📅 Upcoming Horizon"
  echo ""

  local response
  response=$(api_call "${BASE_URL}/api/v1/atomicnebula/digest${query}") || return 1

  echo "$response" | jq '{
    timezone: {
      name: .data.meta.timezone,
      source: .data.meta.timezoneSource,
      localTime: .data.meta.localTime,
      note: .data.meta.temporalContext
    },
    horizon: [.data.upcoming.horizon[] | {
      date,
      dayName,
      isToday,
      isTomorrow,
      tasks: (.items.tasks | length),
      meetings: (.items.meetings | length),
      flagged,
      flagReasons
    }],
    byProject: .data.upcoming.byProject
  }'
}

mark_notified() {
  local keys=""
  local channel="openclaw"
  local expires_after=""
  local notified_at=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keys)
        keys="${2:-}"
        shift 2
        ;;
      --channel)
        channel="${2:-}"
        shift 2
        ;;
      --expires-after)
        expires_after="${2:-}"
        shift 2
        ;;
      --notified-at)
        notified_at="${2:-}"
        shift 2
        ;;
      --env)
        shift 2
        ;;
      --*)
        echo "Error: Unrecognized option '$1' for notified command" >&2
        return 1
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ -z "$keys" ]]; then
    echo "Error: --keys is required for notified command" >&2
    return 1
  fi

  local keys_json
  keys_json=$(printf '%s' "$keys" | jq -Rc 'split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length > 0))')
  if [[ "$(echo "$keys_json" | jq 'length')" -eq 0 ]]; then
    echo "Error: --keys must contain at least one non-empty key" >&2
    return 1
  fi

  local payload
  payload=$(jq -n \
    --argjson notificationKeys "$keys_json" \
    --arg channel "$channel" \
    --arg expiresAfter "$expires_after" \
    --arg notifiedAt "$notified_at" \
    '{
      notificationKeys: $notificationKeys,
      channel: $channel
    }
    + (if $expiresAfter != "" then { expiresAfter: ($expiresAfter | tonumber) } else {} end)
    + (if $notifiedAt != "" then { notifiedAt: ($notifiedAt | tonumber) } else {} end)')

  echo "${ENV_PREFIX}✅ Marking notification keys as notified"
  echo ""

  local response
  response=$(api_call_post "${BASE_URL}/api/v1/atomicnebula/reminders/notified" "$payload") || return 1

  echo "$response" | jq '{
    recorded: .data.recorded,
    alreadyRecorded: .data.alreadyRecorded,
    keys: .data.keys
  }'
}

# Main command parser
case "${1:-}" in
  today)
    shift
    get_today "$@"
    ;;
  briefing)
    shift
    get_briefing "$@"
    ;;
  emails)
    shift
    get_emails "$@"
    ;;
  due)
    shift
    get_due "$@"
    ;;
  upcoming)
    shift
    get_upcoming "$@"
    ;;
  notified)
    shift
    mark_notified "$@"
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

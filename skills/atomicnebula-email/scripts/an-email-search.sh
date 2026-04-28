#!/bin/bash
#
# Atomic Nebula Email Search CLI Helper
#
# Searches across all connected email mailboxes (Exchange + Gmail) via
# provider-native APIs. Supports text search, sender/recipient filters,
# attachment presence, and date ranges.
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

# ── Help ────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "help" ]]; then
  cat << 'USAGE'
Atomic Nebula Email Search CLI

Usage: an-email-search.sh [--env <workspace>] [query] [options]

Arguments:
  query                Free-text search (searches subject + body via provider)

Options:
  --from <addr>        Filter by sender email address or name
  --to <addr>          Filter by recipient email address or name
  --has-attachments    Filter to emails with attachments
  --after <date>       Received after date (ISO 8601, e.g. 2026-01-01)
  --before <date>      Received before date (ISO 8601, e.g. 2026-03-01)
  --mailbox <addr>     Search only this specific mailbox
  --limit <n>          Max results (default: 25, max: 50)
  --env <workspace>    Target workspace slug (e.g., spider, dev)
  -h, --help           Show this help

Examples:
  an-email-search.sh "invoice from Acme"
  an-email-search.sh --from "billing@acme.com" --has-attachments
  an-email-search.sh "renewal" --after 2026-01-01 --before 2026-03-01
  an-email-search.sh --env dev "receipt" --mailbox james@company.com
USAGE
  exit 0
fi

# ── Validation ──────────────────────────────────────────────────────────────
if [[ -z "${API_KEY:-}" ]]; then
  echo "ERROR: No API key found for workspace '${AN_ENV:-default}'. Check assistant workspace config." >&2
  exit 1
fi

for bin in curl jq; do
  if ! command -v "$bin" &>/dev/null; then
    echo "ERROR: Required binary '$bin' not found. Install it first." >&2
    exit 1
  fi
done

# ── Parse arguments ─────────────────────────────────────────────────────────
QUERY=""
FROM=""
TO=""
HAS_ATTACHMENTS=""
AFTER=""
BEFORE=""
MAILBOX=""
LIMIT=""

require_arg() {
  if [[ $# -lt 2 ]] || [[ "$2" == --* ]]; then
    echo "ERROR: $1 requires a value" >&2; exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      require_arg "$@"; FROM="$2"; shift 2 ;;
    --to)
      require_arg "$@"; TO="$2"; shift 2 ;;
    --has-attachments)
      HAS_ATTACHMENTS="true"; shift ;;
    --after)
      require_arg "$@"; AFTER="$2"; shift 2 ;;
    --before)
      require_arg "$@"; BEFORE="$2"; shift 2 ;;
    --mailbox)
      require_arg "$@"; MAILBOX="$2"; shift 2 ;;
    --limit)
      require_arg "$@"
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --limit must be a positive integer, got '$2'" >&2; exit 1
      fi
      LIMIT="$2"; shift 2 ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    *)
      # Positional arg = query text
      if [[ -n "$QUERY" ]]; then
        QUERY="$QUERY $1"
      else
        QUERY="$1"
      fi
      shift ;;
  esac
done

# Must have at least one search criteria
if [[ -z "$QUERY" ]] && [[ -z "$FROM" ]] && [[ -z "$TO" ]] && [[ -z "$HAS_ATTACHMENTS" ]]; then
  echo "ERROR: At least one search criteria required (query text, --from, --to, or --has-attachments)" >&2
  exit 1
fi

# ── Build JSON body ─────────────────────────────────────────────────────────
# Use jq to build the JSON safely (handles escaping of quotes, backslashes, etc.)
BODY=$(jq -n \
  --arg query "$QUERY" \
  --arg from "$FROM" \
  --arg to "$TO" \
  --arg hasAttachments "$HAS_ATTACHMENTS" \
  --arg after "$AFTER" \
  --arg before "$BEFORE" \
  --arg mailbox "$MAILBOX" \
  --arg limit "$LIMIT" \
  '{
    query: (if $query != "" then $query else null end),
    from: (if $from != "" then $from else null end),
    to: (if $to != "" then $to else null end),
    hasAttachments: (if $hasAttachments == "true" then true else null end),
    after: (if $after != "" then $after else null end),
    before: (if $before != "" then $before else null end),
    mailboxAddress: (if $mailbox != "" then $mailbox else null end),
    limit: (if $limit != "" then ($limit | tonumber) else null end)
  } | with_entries(select(.value != null))'
)

# ── Execute search ──────────────────────────────────────────────────────────
PREFIX="$(print_env_prefix)"

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$BODY" \
  "${BASE_URL}/api/v1/atomicnebula/emails/search")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ne 200 ]]; then
  echo "${PREFIX}ERROR: Search failed (HTTP ${HTTP_CODE})" >&2
  echo "$RESPONSE_BODY" | jq -r '.error // .message // "Unknown error"' 2>/dev/null || echo "$RESPONSE_BODY" >&2
  exit 1
fi

# ── Format output ───────────────────────────────────────────────────────────
RESULT_COUNT=$(echo "$RESPONSE_BODY" | jq -r '.data.metadata.totalResults // 0')
MAILBOXES=$(echo "$RESPONSE_BODY" | jq -r '.data.metadata.mailboxesSearched | join(", ")' 2>/dev/null || echo "unknown")
TOTAL_MS=$(echo "$RESPONSE_BODY" | jq -r '.data.metadata.timing.totalMs // "?"')
TRUNCATED=$(echo "$RESPONSE_BODY" | jq -r '.data.metadata.truncated // false')

echo "${PREFIX}Found ${RESULT_COUNT} results across [${MAILBOXES}] in ${TOTAL_MS}ms"
if [[ "$TRUNCATED" == "true" ]]; then
  echo "${PREFIX}(Results truncated — more matches available in mailbox)"
fi

# Print any errors
ERRORS=$(echo "$RESPONSE_BODY" | jq -r '.data.metadata.errors // [] | .[] | "  WARNING: \(.mailboxAddress) — \(.error)"' 2>/dev/null)
if [[ -n "$ERRORS" ]]; then
  echo "$ERRORS"
fi

echo ""

# Print results
echo "$RESPONSE_BODY" | jq -r '
  .data.results[] |
  "---\n" +
  "Subject:  " + .subject + "\n" +
  "From:     " + .from.name + " <" + .from.address + ">\n" +
  "To:       " + ([.to[].address] | join(", ")) + "\n" +
  "Date:     " + .receivedAt + "\n" +
  "Mailbox:  " + .mailboxAddress + " (" + .provider + ")\n" +
  (if .hasAttachments then "Attach:   Yes\n" else "" end) +
  (if .webLink then "Link:     " + .webLink + "\n" else "" end) +
  "Preview:  " + (.bodyPreview | gsub("\n"; " ") | .[0:200]) + "\n"
' 2>/dev/null || echo "(No results or parse error)"

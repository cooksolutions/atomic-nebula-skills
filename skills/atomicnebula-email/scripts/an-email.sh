#!/bin/bash
#
# Atomic Nebula Email CLI — full email surface
#
# Dispatches subcommands to the Atomic Nebula Email API endpoints. Provides
# read, write, draft, and mailbox-management operations across all connected
# Exchange and Gmail mailboxes.
#
# Usage: an-email.sh <subcommand> [args] [--env <workspace>]
#
# Compatibility: written for Bash 3.2 (the version macOS ships) — does not
# use `mapfile`, `declare -A`, or other Bash 4+ features.

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

# ── Help ────────────────────────────────────────────────────────────────────

show_help() {
  cat << 'USAGE'
Atomic Nebula Email CLI

Usage: an-email.sh <subcommand> [args] [--env <workspace>]

READ
  search [query] [--from X] [--to X] [--has-attachments] [--after DATE]
                 [--before DATE] [--mailbox X] [--limit N]
  list           [--mailbox X] [--folder ID] [--contact ID] [--deal ID]
                 [--is-read true|false] [--has-attachments] [--limit N]
  get <emailId>
  content <emailId>
  thread <conversationId> [--mailbox X] [--limit N]
  unread [--folder ID] [--mailbox X]

WRITE (queued)
  send       --mailbox X --to "a@x;b@y" [--cc "c@y"] [--bcc "d@y"] --subject S --body B
             [--body-type html|text] [--importance low|normal|high]
  reply <emailId>   --mailbox X --body B [--body-type html|text] [--reply-all]
  forward <emailId> --mailbox X --to "a@x;b@y" [--cc "c@y"] [--body B]

  Recipient flags (--to/--cc/--bcc) accept multiple addresses separated by
  semicolons (NOT commas — display names like "Cook, James" contain commas).

DRAFTS (synced to provider Drafts folder + AN deep-link)
  draft create   --mailbox X [--to addr] [--cc addr] [--bcc addr]
                 [--subject S] [--body B] [--body-type html|text]
                 [--contact ID] [--deal ID]
  draft reply    <emailId> --mailbox X [--body B] [--body-type html|text] [--reply-all]
  draft forward  <emailId> --mailbox X [--to addr] [--cc addr] [--body B] [--body-type html|text]
  draft list     [--limit N]
  draft get      <draftId>
  draft update   <draftId> [--subject S] [--body B] [--body-type html|text]
                           [--to addr] [--cc addr] [--bcc addr]
  draft send     <draftId>
  draft delete   <draftId>
  draft wait     <draftId>             # poll until syncStatus is synced or failed

MAILBOX
  mailboxes                          # List the connected mailbox addresses
                                     # the API key can act on. Call this if a
                                     # send/draft fails with MAILBOX_NOT_CONNECTED.
  mark-read   <emailId>
  mark-unread <emailId>
  flag        <emailId> --flag notFlagged|flagged|complete
  delete      <emailId>
  delete-thread <conversationId> [--mailbox X]
  promote-contact <emailId> [--first-name F] [--last-name L] [--email E]
                            [--company-id C] [--job-title J] [--phone P]

GENERAL
  --env <workspace>  Target workspace (default: spider)
  -h, --help         Show this help

Examples
  an-email.sh search "invoice from Acme"
  an-email.sh draft reply 9f3e1c7a... --mailbox james@co.uk \
              --body "<p>Thanks for the brief — here are my questions...</p>"
USAGE
}

if [[ "${1:-}" == "" ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

# ── Strip --env from args, resolve workspace ────────────────────────────────

NEW_ARGS=()
_skip=false
for _arg in "$@"; do
  if $_skip; then _skip=false; continue; fi
  if [[ "$_arg" == "--env" ]]; then _skip=true; continue; fi
  NEW_ARGS+=("$_arg")
done

eval "$(extract_env_flag "$@")"
resolve_an_env "$ENV_ARG"

if [[ -z "${API_KEY:-}" ]]; then
  echo "ERROR: No API key found for workspace '${AN_ENV:-default}'. Check assistant workspace config." >&2
  exit 1
fi
for bin in curl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: '$bin' not installed." >&2; exit 1; }
done

# Reset positional params to the stripped-of-env list. Guard against unbound
# array expansion (Bash 3.2 + `set -u` quirk when the array is empty).
if [[ ${#NEW_ARGS[@]} -gt 0 ]]; then
  set -- "${NEW_ARGS[@]}"
else
  set --
fi

SUB="${1:-}"
[[ -z "$SUB" ]] && { show_help; exit 0; }
shift || true

# ── Generic helpers (Bash 3.2 compatible) ───────────────────────────────────

# Parallel arrays describing every recognised --flag and how to map it onto
# the JSON request body. Filled by `declare_flag_map`.
FLAG_NAMES=()
FLAG_KEYS=()
FLAG_TYPES=()  # one of: string | array | bool | number

_add_flag() {
  FLAG_NAMES[${#FLAG_NAMES[@]}]="$1"
  FLAG_KEYS[${#FLAG_KEYS[@]}]="$2"
  FLAG_TYPES[${#FLAG_TYPES[@]}]="$3"
}

declare_flag_map() {
  FLAG_NAMES=()
  FLAG_KEYS=()
  FLAG_TYPES=()
  _add_flag --mailbox        mailboxAddress    string
  _add_flag --search         search            string
  _add_flag --query          query             string
  _add_flag --from           from              string
  _add_flag --to             to                array
  _add_flag --cc             cc                array
  _add_flag --bcc            bcc               array
  _add_flag --subject        subject           string
  _add_flag --body           body              string
  _add_flag --body-type      bodyType          string
  _add_flag --importance     importance        string
  _add_flag --has-attachments hasAttachments   bool
  _add_flag --after          after             string
  _add_flag --before         before            string
  _add_flag --limit          limit             number
  _add_flag --reply-all      replyAll          bool
  _add_flag --flag           flag              string
  _add_flag --folder         folderId          string
  _add_flag --contact        contactId         string
  _add_flag --deal           dealId            string
  _add_flag --is-read        isRead            string
  _add_flag --first-name     firstName         string
  _add_flag --last-name      lastName          string
  _add_flag --email          contactEmail      string
  _add_flag --company-id     primaryCompanyId  string
  _add_flag --job-title      jobTitle          string
  _add_flag --phone          phone             string
}

# Looks up a flag by name. On match, sets globals FLAG_KEY and FLAG_TYPE
# and returns 0; otherwise returns 1.
lookup_flag() {
  local needle="$1" i n="${#FLAG_NAMES[@]}"
  i=0
  while [[ $i -lt $n ]]; do
    if [[ "${FLAG_NAMES[$i]}" == "$needle" ]]; then
      FLAG_KEY="${FLAG_KEYS[$i]}"
      FLAG_TYPE="${FLAG_TYPES[$i]}"
      return 0
    fi
    i=$((i+1))
  done
  return 1
}

# Build a JSON object body from `--key value` pairs in the remaining args.
# Sets globals JSON_BODY and POSITIONAL_ARG.
# If a positional (non-flag) arg is supplied with no `query` flag set, it is
# treated as the search query (preserves the historical `an-email-search.sh`
# UX).
build_json_body() {
  local positional_key="${1:-query}"
  if [[ $# -gt 0 ]]; then shift; fi
  declare_flag_map
  JSON_BODY="{}"
  POSITIONAL_ARG=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --*)
        if ! lookup_flag "$1"; then
          echo "ERROR: Unknown flag: $1" >&2
          return 1
        fi
        case "$FLAG_TYPE" in
          bool)
            JSON_BODY=$(echo "$JSON_BODY" | jq --arg k "$FLAG_KEY" '. + {($k): true}')
            shift
            ;;
          number)
            if [[ -z "${2:-}" ]] || [[ "$2" == --* ]]; then
              echo "ERROR: $1 requires a value" >&2; return 1
            fi
            if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
              echo "ERROR: $1 must be a positive integer (>= 1)" >&2; return 1
            fi
            JSON_BODY=$(echo "$JSON_BODY" | jq --arg k "$FLAG_KEY" --argjson v "$2" '. + {($k): $v}')
            shift 2
            ;;
          array)
            if [[ -z "${2:-}" ]] || [[ "$2" == --* ]]; then
              echo "ERROR: $1 requires a value" >&2; return 1
            fi
            # Multi-value flags use `;` as the separator. Email display names
            # legitimately contain commas (e.g. "Cook, James <j@x>") so a
            # comma-split would corrupt the address list. Semicolon is not
            # legal anywhere in an RFC 5322 address, making it a safe
            # separator. Single values without `;` work too — split() on a
            # string with no separator returns a single-element array.
            local arr_json
            arr_json=$(printf '%s' "$2" | jq -R 'split(";") | map(ltrimstr(" ") | rtrimstr(" ")) | map(select(length > 0))')
            JSON_BODY=$(echo "$JSON_BODY" | jq --arg k "$FLAG_KEY" --argjson v "$arr_json" '. + {($k): $v}')
            shift 2
            ;;
          string)
            if [[ -z "${2:-}" ]] || [[ "$2" == --* ]]; then
              echo "ERROR: $1 requires a value" >&2; return 1
            fi
            JSON_BODY=$(echo "$JSON_BODY" | jq --arg k "$FLAG_KEY" --arg v "$2" '. + {($k): $v}')
            shift 2
            ;;
        esac
        ;;
      *)
        if [[ -z "$POSITIONAL_ARG" ]]; then
          POSITIONAL_ARG="$1"
        else
          POSITIONAL_ARG="$POSITIONAL_ARG $1"
        fi
        shift
        ;;
    esac
  done
  # Promote positional arg to the command-specific search key if not already set.
  if [[ -n "$POSITIONAL_ARG" ]] && ! echo "$JSON_BODY" | jq -e --arg k "$positional_key" 'has($k)' >/dev/null 2>&1; then
    JSON_BODY=$(echo "$JSON_BODY" | jq --arg k "$positional_key" --arg q "$POSITIONAL_ARG" '. + {($k): $q}')
  fi
}

# Convert a JSON object into a URL-encoded query string.
build_query_string() {
  echo "$1" | jq -r 'to_entries | map("\(.key)=\(.value | tostring | @uri)") | join("&")'
}

default_body_type_html() {
  if echo "$JSON_BODY" | jq -e 'has("body") and (has("bodyType") | not)' >/dev/null 2>&1; then
    JSON_BODY=$(echo "$JSON_BODY" | jq '. + {bodyType: "html"}')
  fi
}

# HTTP wrapper. Prints the response body (pretty-printed) on success, exits
# non-zero on HTTP >= 400 with the error printed to stderr.
#
# Empty / 204 responses are handled — `jq .` on an empty string errors with
# `parse error: (null)`, so we synthesise `{"status":<code>}` instead.
api_call() {
  local method="$1" path="$2" body="${3:-}"
  local resp http_code body_str
  if [[ -n "$body" ]]; then
    resp=$(curl -s -w "\n%{http_code}" -X "$method" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d "$body" "${BASE_URL}${path}")
  else
    resp=$(curl -s -w "\n%{http_code}" -X "$method" \
      -H "Authorization: Bearer $API_KEY" \
      "${BASE_URL}${path}")
  fi
  http_code=$(echo "$resp" | tail -1)
  body_str=$(echo "$resp" | sed '$d')
  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: $method $path -> HTTP $http_code" >&2
    if [[ -n "$body_str" ]]; then
      echo "$body_str" | jq . 2>/dev/null || echo "$body_str" >&2
    fi
    exit 1
  fi
  if [[ -z "$body_str" ]]; then
    # No body (e.g. HTTP 204 No Content). Synthesize a minimal JSON so
    # downstream `| jq` chains in the user's shell continue to work.
    jq -n --arg status "$http_code" '{ok: true, status: ($status | tonumber)}'
  else
    echo "$body_str" | jq . 2>/dev/null || echo "$body_str"
  fi
}

warn_missing_search_ids() {
  local body="$1" missing total
  missing=$(printf '%s' "$body" | jq '[.data.results[]? | select((.id // "") == "")] | length' 2>/dev/null || echo 0)
  total=$(printf '%s' "$body" | jq '.data.results | length' 2>/dev/null || echo 0)
  if [[ "$missing" =~ ^[0-9]+$ ]] && [[ "$total" =~ ^[0-9]+$ ]] && [[ "$missing" -gt 0 ]]; then
    echo "WARNING: $missing/$total search result(s) have no AN canonical id. Do not use exchangeId/gmailId with get/content/reply/draft endpoints. The provider found the message, but it is not currently addressable in AN; retry after mailbox sync or use list --search to look for an ingested copy." >&2
  fi
}

# Post a draft create / reply / forward and auto-poll the resulting draft
# until provider sync reaches a terminal state (`synced` or `failed`).
# Prints the final draft state as JSON on stdout.
#
# Why poll here instead of in the API: the create endpoint persists the
# local draft and returns immediately with `syncStatus: "pending"`. The
# provider sync runs in the background. Without this loop the assistant
# would only see the optimistic "pending" response and not know when (or
# whether) the provider draft actually landed. Reporting the truth back
# to the assistant is cheap on the client side and avoids forcing every
# server-side caller to pay the synchronous Azure round-trip.
post_draft_and_wait() {
  local method="$1" path="$2" body="$3"
  local resp http_code body_str draft_id status sync_error attempt
  resp=$(curl -s -w "\n%{http_code}" -X "$method" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$body" "${BASE_URL}${path}")
  http_code=$(echo "$resp" | tail -1)
  body_str=$(echo "$resp" | sed '$d')
  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: $method $path -> HTTP $http_code" >&2
    if [[ -n "$body_str" ]]; then
      echo "$body_str" | jq . 2>/dev/null >&2 || echo "$body_str" >&2
    fi
    exit 1
  fi
  draft_id=$(echo "$body_str" | jq -r '.data.draftId // ""')
  if [[ -z "$draft_id" ]]; then
    # Server didn't return a draftId — print the response verbatim so
    # the caller can decide what to do.
    echo "$body_str" | jq .
    return
  fi
  attempt=1
  while [[ $attempt -le 15 ]]; do
    sleep 1
    local poll_resp poll_code poll_body
    poll_resp=$(curl -s -w "\n%{http_code}" \
      -H "Authorization: Bearer $API_KEY" \
      "${BASE_URL}/api/v1/atomicnebula/emails/drafts/${draft_id}")
    poll_code=$(echo "$poll_resp" | tail -1)
    poll_body=$(echo "$poll_resp" | sed '$d')
    if [[ "$poll_code" -ge 400 ]]; then
      echo "ERROR: poll attempt $attempt -> HTTP $poll_code" >&2
      echo "$poll_body" | jq . 2>/dev/null >&2 || echo "$poll_body" >&2
      exit 1
    fi
    status=$(echo "$poll_body" | jq -r '.data.syncStatus // "unknown"')
    if [[ "$status" == "synced" ]] || [[ "$status" == "failed" ]]; then
      # Surface the terminal draft state. If failed, the response body
      # carries `syncError` and we exit non-zero so the assistant sees
      # the failure.
      echo "$poll_body" | jq .
      if [[ "$status" == "failed" ]]; then
        sync_error=$(echo "$poll_body" | jq -r '.data.syncError // "unknown error"')
        echo "ERROR: draft $draft_id failed to sync: $sync_error" >&2
        exit 1
      fi
      return
    fi
    attempt=$((attempt + 1))
  done
  # Timeout — surface whatever state we last saw with a warning.
  echo "WARNING: draft $draft_id still pending after 15 polls; provider sync may complete asynchronously" >&2
  echo "$body_str" | jq .
}

# ── Subcommand dispatch ─────────────────────────────────────────────────────

case "$SUB" in
  # ── MAILBOX DISCOVERY ────────────────────────────────────────────────────
  # List the connected mailbox addresses the API key can act on. The
  # `mailboxAddress` value passed to `send`, `reply`, `forward`, `draft *`
  # MUST be one of the `address` values returned here. If a write call
  # returns MAILBOX_NOT_CONNECTED, run this and retry with a valid address.
  mailboxes)
    api_call GET /api/v1/atomicnebula/mailboxes
    ;;

  # ── READ ─────────────────────────────────────────────────────────────────
  search)
    build_json_body query "$@"
    RESPONSE=$(api_call POST /api/v1/atomicnebula/emails/search "$JSON_BODY")
    warn_missing_search_ids "$RESPONSE"
    printf '%s\n' "$RESPONSE"
    ;;
  list)
    build_json_body search "$@"
    QS=$(build_query_string "$JSON_BODY")
    if [[ -n "$QS" ]]; then
      api_call GET "/api/v1/atomicnebula/emails?$QS"
    else
      api_call GET "/api/v1/atomicnebula/emails"
    fi
    ;;
  get)
    [[ -z "${1:-}" ]] && { echo "ERROR: get requires <emailId>" >&2; exit 1; }
    api_call GET "/api/v1/atomicnebula/emails/$1"
    ;;
  content)
    [[ -z "${1:-}" ]] && { echo "ERROR: content requires <emailId>" >&2; exit 1; }
    api_call GET "/api/v1/atomicnebula/emails/$1/content"
    ;;
  thread)
    [[ -z "${1:-}" ]] && { echo "ERROR: thread requires <conversationId>" >&2; exit 1; }
    CONV_ID="$1"; shift
    build_json_body query "$@"
    QS=$(build_query_string "$JSON_BODY")
    if [[ -n "$QS" ]]; then
      api_call GET "/api/v1/atomicnebula/emails/thread/$CONV_ID?$QS"
    else
      api_call GET "/api/v1/atomicnebula/emails/thread/$CONV_ID"
    fi
    ;;
  unread)
    build_json_body query "$@"
    QS=$(build_query_string "$JSON_BODY")
    if [[ -n "$QS" ]]; then
      api_call GET "/api/v1/atomicnebula/emails/unread?$QS"
    else
      api_call GET "/api/v1/atomicnebula/emails/unread"
    fi
    ;;

  # ── WRITE ────────────────────────────────────────────────────────────────
  send)
    build_json_body query "$@"
    api_call POST /api/v1/atomicnebula/emails/send "$JSON_BODY"
    ;;
  reply)
    [[ -z "${1:-}" ]] && { echo "ERROR: reply requires <emailId>" >&2; exit 1; }
    EID="$1"; shift
    build_json_body query "$@"
    api_call POST "/api/v1/atomicnebula/emails/$EID/reply" "$JSON_BODY"
    ;;
  forward)
    [[ -z "${1:-}" ]] && { echo "ERROR: forward requires <emailId>" >&2; exit 1; }
    EID="$1"; shift
    build_json_body query "$@"
    api_call POST "/api/v1/atomicnebula/emails/$EID/forward" "$JSON_BODY"
    ;;
  mark-read)
    [[ -z "${1:-}" ]] && { echo "ERROR: mark-read requires <emailId>" >&2; exit 1; }
    api_call POST "/api/v1/atomicnebula/emails/$1/read" '{"isRead":true}'
    ;;
  mark-unread)
    [[ -z "${1:-}" ]] && { echo "ERROR: mark-unread requires <emailId>" >&2; exit 1; }
    api_call POST "/api/v1/atomicnebula/emails/$1/read" '{"isRead":false}'
    ;;
  flag)
    [[ -z "${1:-}" ]] && { echo "ERROR: flag requires <emailId>" >&2; exit 1; }
    EID="$1"; shift
    build_json_body query "$@"
    api_call POST "/api/v1/atomicnebula/emails/$EID/flag" "$JSON_BODY"
    ;;
  delete)
    [[ -z "${1:-}" ]] && { echo "ERROR: delete requires <emailId>" >&2; exit 1; }
    api_call DELETE "/api/v1/atomicnebula/emails/$1"
    ;;
  delete-thread)
    [[ -z "${1:-}" ]] && { echo "ERROR: delete-thread requires <conversationId>" >&2; exit 1; }
    CONV_ID="$1"; shift
    build_json_body query "$@"
    QS=$(build_query_string "$JSON_BODY")
    if [[ -n "$QS" ]]; then
      api_call DELETE "/api/v1/atomicnebula/emails/thread/$CONV_ID?$QS"
    else
      api_call DELETE "/api/v1/atomicnebula/emails/thread/$CONV_ID"
    fi
    ;;
  promote-contact)
    [[ -z "${1:-}" ]] && { echo "ERROR: promote-contact requires <emailId>" >&2; exit 1; }
    EID="$1"; shift
    build_json_body query "$@"
    api_call POST "/api/v1/atomicnebula/emails/$EID/promote-contact" "$JSON_BODY"
    ;;

  # ── DRAFTS ───────────────────────────────────────────────────────────────
  draft)
    DSUB="${1:-}"
    [[ -z "$DSUB" ]] && { show_help; exit 0; }
    shift
    case "$DSUB" in
      create)
        build_json_body query "$@"
        default_body_type_html
        post_draft_and_wait POST /api/v1/atomicnebula/emails/draft "$JSON_BODY"
        ;;
      reply)
        [[ -z "${1:-}" ]] && { echo "ERROR: draft reply requires <emailId>" >&2; exit 1; }
        EID="$1"; shift
        build_json_body query "$@"
        default_body_type_html
        post_draft_and_wait POST "/api/v1/atomicnebula/emails/$EID/draft-reply" "$JSON_BODY"
        ;;
      forward)
        [[ -z "${1:-}" ]] && { echo "ERROR: draft forward requires <emailId>" >&2; exit 1; }
        EID="$1"; shift
        build_json_body query "$@"
        default_body_type_html
        post_draft_and_wait POST "/api/v1/atomicnebula/emails/$EID/draft-forward" "$JSON_BODY"
        ;;
      list)
        build_json_body query "$@"
        QS=$(build_query_string "$JSON_BODY")
        if [[ -n "$QS" ]]; then
          api_call GET "/api/v1/atomicnebula/emails/drafts?$QS"
        else
          api_call GET "/api/v1/atomicnebula/emails/drafts"
        fi
        ;;
      get)
        [[ -z "${1:-}" ]] && { echo "ERROR: draft get requires <draftId>" >&2; exit 1; }
        api_call GET "/api/v1/atomicnebula/emails/drafts/$1"
        ;;
      update)
        [[ -z "${1:-}" ]] && { echo "ERROR: draft update requires <draftId>" >&2; exit 1; }
        DID="$1"; shift
        build_json_body query "$@"
        default_body_type_html
        api_call PATCH "/api/v1/atomicnebula/emails/drafts/$DID" "$JSON_BODY"
        ;;
      delete)
        [[ -z "${1:-}" ]] && { echo "ERROR: draft delete requires <draftId>" >&2; exit 1; }
        api_call DELETE "/api/v1/atomicnebula/emails/drafts/$1"
        ;;
      send)
        [[ -z "${1:-}" ]] && { echo "ERROR: draft send requires <draftId>" >&2; exit 1; }
        api_call POST "/api/v1/atomicnebula/emails/drafts/$1/send" ""
        ;;
      wait)
        [[ -z "${1:-}" ]] && { echo "ERROR: draft wait requires <draftId>" >&2; exit 1; }
        DID="$1"
        ATTEMPT=1
        while [[ $ATTEMPT -le 10 ]]; do
          # Capture HTTP code separately so we can break early on auth /
          # not-found rather than silently looping all 10 attempts.
          POLL_RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $API_KEY" \
            "${BASE_URL}/api/v1/atomicnebula/emails/drafts/$DID")
          POLL_CODE=$(echo "$POLL_RESP" | tail -1)
          POLL_BODY=$(echo "$POLL_RESP" | sed '$d')
          if [[ "$POLL_CODE" -ge 400 ]]; then
            echo "[attempt $ATTEMPT] poll failed: HTTP $POLL_CODE" >&2
            echo "$POLL_BODY" | jq . 2>/dev/null >&2 || echo "$POLL_BODY" >&2
            exit 1
          fi
          STATUS=$(echo "$POLL_BODY" | jq -r '.data.syncStatus // "unknown"')
          echo "[attempt $ATTEMPT] syncStatus=$STATUS"
          if [[ "$STATUS" == "synced" ]] || [[ "$STATUS" == "failed" ]]; then break; fi
          sleep 1
          ATTEMPT=$((ATTEMPT+1))
        done
        api_call GET "/api/v1/atomicnebula/emails/drafts/$DID"
        ;;
      ""|--help|-h)
        show_help
        exit 0
        ;;
      *)
        echo "ERROR: Unknown draft subcommand: $DSUB" >&2
        echo "Run 'an-email.sh --help' for usage." >&2
        exit 1
        ;;
    esac
    ;;

  *)
    echo "ERROR: Unknown subcommand: $SUB" >&2
    echo "Run 'an-email.sh --help' for usage." >&2
    exit 1
    ;;
esac

#!/bin/bash
#
# Quick workspace discovery for Atomic Nebula assistant skills.
# Lists all configured workspaces with API key status and connectivity.
#
# Usage:
#   an-env-list.sh              # List all workspaces
#   an-env-list.sh --check      # List + health check each endpoint
#   an-env-list.sh --json       # JSON output for programmatic use
#

set -euo pipefail

NEUTRAL_CONFIG_FILE="${AN_ASSISTANT_CONFIG_FILE:-${HOME}/.config/circeaura/assistant-workspaces.json}"
OPENCLAW_CONFIG_FILE="${AN_OPENCLAW_CONFIG_FILE:-${HOME}/.openclaw/openclaw.json}"
CHECK_MODE=false
JSON_MODE=false
CONFIG_SOURCE=""
CONFIG_PAYLOAD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_MODE=true; shift ;;
    --json)  JSON_MODE=true; shift ;;
    -h|--help)
      echo "Usage: an-env-list.sh [--check] [--json]"
      echo "  --check   Health-check each endpoint (adds ~1s per workspace)"
      echo "  --json    Output as JSON"
      exit 0
      ;;
    *) shift ;;
  esac
done

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required" >&2
  exit 1
fi

if [[ -f "$NEUTRAL_CONFIG_FILE" ]]; then
  CONFIG_SOURCE="$NEUTRAL_CONFIG_FILE"
  CONFIG_PAYLOAD=$(cat "$NEUTRAL_CONFIG_FILE")
elif [[ -f "$OPENCLAW_CONFIG_FILE" ]]; then
  CONFIG_SOURCE="$OPENCLAW_CONFIG_FILE"
  CONFIG_PAYLOAD=$(jq -r '.plugins.entries["atomicnebula-webhook"].config // empty' "$OPENCLAW_CONFIG_FILE" 2>/dev/null)
else
  echo "Error: no assistant workspace config found" >&2
  echo "Checked: $NEUTRAL_CONFIG_FILE and $OPENCLAW_CONFIG_FILE" >&2
  exit 1
fi

if [[ -z "$CONFIG_PAYLOAD" ]]; then
  echo "Error: no workspace config found in $CONFIG_SOURCE" >&2
  exit 1
fi

# Resolve default workspace — accept both new and legacy key names
DEFAULT_WS=$(echo "$CONFIG_PAYLOAD" | jq -r '.defaultWorkspace // .defaultEnvironment // "none"')

# Resolve workspace entries — accept both new and legacy key names
WS_KEY=$(echo "$CONFIG_PAYLOAD" | jq -r 'if .workspaces then "workspaces" elif .environments then "environments" else "workspaces" end')

check_health() {
  local url="$1"
  if [[ -z "$url" ]]; then
    echo "no-url"
    return
  fi
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "${url}/api/health" 2>/dev/null || echo "000")
  if [[ "$status" == "000" ]]; then
    echo "unreachable"
  elif [[ "$status" -ge 200 && "$status" -lt 400 ]]; then
    echo "ok"
  else
    echo "http-${status}"
  fi
}

if $JSON_MODE; then
  if $CHECK_MODE; then
    echo "$CONFIG_PAYLOAD" | jq -r ".[\"${WS_KEY}\"] // {} | keys[]" | while read -r slug; do
      base_url=$(echo "$CONFIG_PAYLOAD" | jq -r ".[\"${WS_KEY}\"][\"${slug}\"].baseUrl // empty")
      health=$(check_health "$base_url")
      echo "${slug}=${health}"
    done | {
      health_map=""
      while IFS='=' read -r s h; do
        health_map="${health_map}\"${s}\": \"${h}\","
      done
      health_map="{${health_map%,}}"
      echo "$CONFIG_PAYLOAD" | jq --argjson health "$health_map" --arg def "$DEFAULT_WS" --arg wskey "$WS_KEY" --arg source "$CONFIG_SOURCE" '{
        source: $source,
        defaultWorkspace: (.defaultWorkspace // .defaultEnvironment),
        workspaces: (.[$wskey] // {} | to_entries | map({
          key: .key,
          value: {
            label: .value.label,
            baseUrl: .value.baseUrl,
            hasApiKey: (.value.apiKey != null),
            hasAuthToken: (.value.authToken != null),
            hasSigningSecret: (.value.signingSecret != null),
            isDefault: (.key == $def),
            health: ($health[.key] // "skipped")
          }
        }) | from_entries)
      }'
    }
  else
    echo "$CONFIG_PAYLOAD" | jq --arg def "$DEFAULT_WS" --arg wskey "$WS_KEY" --arg source "$CONFIG_SOURCE" '{
      source: $source,
      defaultWorkspace: (.defaultWorkspace // .defaultEnvironment),
      workspaces: (.[$wskey] // {} | to_entries | map({
        key: .key,
        value: {
          label: .value.label,
          baseUrl: .value.baseUrl,
          hasApiKey: (.value.apiKey != null),
          hasAuthToken: (.value.authToken != null),
          hasSigningSecret: (.value.signingSecret != null),
          isDefault: (.key == $def)
        }
      }) | from_entries)
    }'
  fi
else
  # Table output
  header_fmt="%-18s %-30s %-7s %-8s %-8s %-8s %s"
  if $CHECK_MODE; then
    header_fmt="%-18s %-30s %-7s %-8s %-8s %-8s %-12s %s"
  fi

  echo ""
  echo "Config: $CONFIG_SOURCE"
  echo ""
  if $CHECK_MODE; then
    printf "$header_fmt\n" "WORKSPACE" "LABEL" "DEFAULT" "API_KEY" "AUTH" "SIGNING" "HEALTH" "BASE_URL"
    printf "$header_fmt\n" "---" "---" "---" "---" "---" "---" "---" "---"
  else
    printf "$header_fmt\n" "WORKSPACE" "LABEL" "DEFAULT" "API_KEY" "AUTH" "SIGNING" "BASE_URL"
    printf "$header_fmt\n" "---" "---" "---" "---" "---" "---" "---"
  fi

  echo "$CONFIG_PAYLOAD" | jq -r ".[\"${WS_KEY}\"] // {} | keys[]" | sort | while read -r slug; do
    entry=$(echo "$CONFIG_PAYLOAD" | jq -c ".[\"${WS_KEY}\"][\"${slug}\"]")
    label=$(echo "$entry" | jq -r '.label // "—"')
    base_url=$(echo "$entry" | jq -r '.baseUrl // "—"')
    has_api_key=$(echo "$entry" | jq -r 'if .apiKey then "yes" else "no" end')
    has_auth=$(echo "$entry" | jq -r 'if .authToken then "yes" else "no" end')
    has_signing=$(echo "$entry" | jq -r 'if .signingSecret then "yes" else "no" end')
    is_default="no"
    [[ "$slug" == "$DEFAULT_WS" ]] && is_default="*yes*"

    if $CHECK_MODE; then
      health=$(check_health "$(echo "$entry" | jq -r '.baseUrl // empty')")
      printf "$header_fmt\n" "$slug" "$label" "$is_default" "$has_api_key" "$has_auth" "$has_signing" "$health" "$base_url"
    else
      printf "$header_fmt\n" "$slug" "$label" "$is_default" "$has_api_key" "$has_auth" "$has_signing" "$base_url"
    fi
  done

  echo ""
  ws_count=$(echo "$CONFIG_PAYLOAD" | jq -r ".[\"${WS_KEY}\"] // {} | length")
  key_count=$(echo "$CONFIG_PAYLOAD" | jq -r "[.[\"${WS_KEY}\"] // {} | to_entries[] | select(.value.apiKey != null)] | length")
  echo "${ws_count} workspace(s), ${key_count} with API keys, default: ${DEFAULT_WS}"
fi

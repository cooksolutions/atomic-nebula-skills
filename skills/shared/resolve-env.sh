#!/bin/bash
#
# Shared workspace resolver for Atomic Nebula assistant skill scripts.
#
# Resolves workspace-specific API keys and base URLs from environment
# variables, neutral CirceAura assistant config, or legacy OpenClaw config.
#
# Usage:
#   source "$(dirname "$0")/../../shared/resolve-env.sh"
#   resolve_an_env "$ENV_ARG"
#   # Now BASE_URL, API_KEY, and AN_ENV are set
#

AN_ASSISTANT_CONFIG_FILE="${AN_ASSISTANT_CONFIG_FILE:-${HOME}/.config/circeaura/assistant-workspaces.json}"
AN_OPENCLAW_CONFIG_FILE="${AN_OPENCLAW_CONFIG_FILE:-${HOME}/.openclaw/openclaw.json}"

read_neutral_workspace_entry() {
  local env="$1"
  local config_file="$2"

  if [[ ! -f "$config_file" ]] || ! command -v jq &>/dev/null; then
    return 1
  fi

  if [[ -z "$env" ]]; then
    env=$(jq -r '.defaultWorkspace // .defaultEnvironment // empty' "$config_file" 2>/dev/null || true)
  fi

  if [[ -z "$env" ]]; then
    return 1
  fi

  local ws_entry=""
  ws_entry=$(jq -r ".workspaces[\"${env}\"] // .environments[\"${env}\"] // empty" "$config_file" 2>/dev/null || true)
  if [[ -z "$ws_entry" ]]; then
    return 1
  fi

  local cfg_base_url cfg_api_key
  cfg_base_url=$(echo "$ws_entry" | jq -r '.baseUrl // empty' 2>/dev/null || true)
  cfg_api_key=$(echo "$ws_entry" | jq -r '.apiKey // empty' 2>/dev/null || true)

  if [[ -z "$cfg_base_url" && -z "$cfg_api_key" ]]; then
    return 1
  fi

  BASE_URL="${cfg_base_url:-}"
  API_KEY="${cfg_api_key:-}"
  AN_ENV="$env"
  return 0
}

read_openclaw_workspace_entry() {
  local env="$1"
  local config_file="$2"

  if [[ ! -f "$config_file" ]] || ! command -v jq &>/dev/null; then
    return 1
  fi

  if [[ -z "$env" ]]; then
    env=$(jq -r '
      .plugins.entries["atomicnebula-webhook"].config.defaultWorkspace
      // .plugins.entries["atomicnebula-webhook"].config.defaultEnvironment
      // empty
    ' "$config_file" 2>/dev/null || true)
  fi

  if [[ -z "$env" ]]; then
    return 1
  fi

  local ws_entry=""
  ws_entry=$(jq -r ".plugins.entries[\"atomicnebula-webhook\"].config.workspaces[\"${env}\"] // .plugins.entries[\"atomicnebula-webhook\"].config.environments[\"${env}\"] // empty" "$config_file" 2>/dev/null || true)
  if [[ -z "$ws_entry" ]]; then
    return 1
  fi

  local cfg_base_url cfg_api_key
  cfg_base_url=$(echo "$ws_entry" | jq -r '.baseUrl // empty' 2>/dev/null || true)
  cfg_api_key=$(echo "$ws_entry" | jq -r '.apiKey // empty' 2>/dev/null || true)

  if [[ -z "$cfg_base_url" && -z "$cfg_api_key" ]]; then
    return 1
  fi

  BASE_URL="${cfg_base_url:-}"
  API_KEY="${cfg_api_key:-}"
  AN_ENV="$env"
  return 0
}

resolve_an_env() {
  local env="${1:-}"

  # Environment variables are first so CI/session overrides are explicit.
  case "$env" in
    dev|development)
      BASE_URL="${ATOMICNEBULA_DEV_BASE_URL:-https://dev.atomicnebula.com:5173}"
      API_KEY="${ATOMICNEBULA_DEV_API_KEY:-}"
      AN_ENV="dev"
      [[ -n "$API_KEY" ]] && return
      ;;
    staging)
      BASE_URL="${ATOMICNEBULA_STAGING_BASE_URL:-https://staging.atomicnebula.com}"
      API_KEY="${ATOMICNEBULA_STAGING_API_KEY:-}"
      AN_ENV="staging"
      [[ -n "$API_KEY" ]] && return
      ;;
    *)
      BASE_URL="${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}"
      API_KEY="${ATOMICNEBULA_API_KEY:-}"
      AN_ENV="${env:-production}"
      [[ -n "$API_KEY" ]] && return
      ;;
  esac

  if read_neutral_workspace_entry "$env" "$AN_ASSISTANT_CONFIG_FILE"; then
    return
  fi

  if read_openclaw_workspace_entry "$env" "$AN_OPENCLAW_CONFIG_FILE"; then
    return
  fi
}

# Extract --env flag from args and return remaining args.
# Sets ENV_ARG and prints the cleaned argument list (null-delimited).
# Usage:
#   eval "$(extract_env_flag "$@")"
#   # Now ENV_ARG is set and positional params are cleaned
extract_env_flag() {
  local env_arg=""
  local cleaned=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env)
        if [[ $# -ge 2 ]]; then
          env_arg="$2"
          shift 2
        else
          echo "echo 'Error: --env requires a value (workspace slug or: dev, staging, production)' >&2; exit 1"
          return
        fi
        ;;
      --env=*)
        env_arg="${1#--env=}"
        shift
        ;;
      *)
        cleaned+=("$1")
        shift
        ;;
    esac
  done

  # Output commands to eval: set ENV_ARG and reset positional params
  printf 'ENV_ARG=%q\n' "$env_arg"
  printf 'set --'
  for arg in "${cleaned[@]}"; do
    printf ' %q' "$arg"
  done
  printf '\n'
}

# Print workspace prefix for non-production workspaces
print_env_prefix() {
  if [[ "${AN_ENV:-production}" != "production" ]]; then
    echo "[${AN_ENV}] "
  fi
}

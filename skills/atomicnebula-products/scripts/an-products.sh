#!/bin/bash
#
# Atomic Nebula Products CLI Helper
#
# Read-only product catalogue lookup through the Atomic Nebula external REST API.
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

usage() {
  cat << 'USAGE'
Atomic Nebula Products CLI

Usage: an-products.sh [--env <workspace>] <command> [options]

Commands:
  lookup                     Search products by query, SKU, or product id
  stock                      Lookup products and return stock-relevant fields
  price                      Lookup products and return price-relevant fields
  list                       List product catalogue entries
  get <productId>            Get one product

Global Options:
  --env <env>                Target workspace slug (e.g., spider, dev, circeaurasupport)

lookup / stock / price Options:
  --query <text>             Product name or description search
  --sku <text>               Exact SKU lookup
  --product-id <id>          Canonical Atomic Nebula product id
  --limit <n>                Max matches, default 10, max 25

list Options:
  --search <text>
  --category <text>
  --is-recurring <true|false>
  --billing-frequency <text>
  --pipeline-id <id>
  --stage-id <id>
  --sort-by <field>
  --sort-order <asc|desc>
  --limit <n>
  --cursor <token>

Examples:
  an-products.sh lookup --query "printer cartridge"
  an-products.sh lookup --sku "SKU-123"
  an-products.sh stock --query "printer cartridge"
  an-products.sh price --sku "SKU-123"
  an-products.sh list --search "support" --limit 20
  an-products.sh get PRODUCT-ID
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

urlencode() {
  jq -rn --arg v "$1" '$v|@uri'
}

query_params=()
add_query_param() {
  local key="$1"
  local value="$2"
  if [[ -n "$value" ]]; then
    query_params+=("${key}=$(urlencode "$value")")
  fi
}

build_query() {
  if [[ ${#query_params[@]} -eq 0 ]]; then
    echo ""
    return
  fi
  local IFS="&"
  echo "?${query_params[*]}"
}

request_json() {
  local url="$1"
  local response
  response=$(curl "${CURL_BASE[@]}" -w "\n%{http_code}" "$url")
  local code
  local body
  code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  echo "$body" | jq . 2>/dev/null || echo "$body"
  if [[ "$code" -lt 200 || "$code" -ge 300 ]]; then
    exit 1
  fi
}

parse_lookup_params() {
  query_params=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --query) add_query_param "query" "$2"; shift 2 ;;
      --sku) add_query_param "sku" "$2"; shift 2 ;;
      --product-id) add_query_param "productId" "$2"; shift 2 ;;
      --limit) add_query_param "limit" "$2"; shift 2 ;;
      --env) shift 2 ;;
      *) echo "Unknown lookup option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
}

lookup_products() {
  parse_lookup_params "$@"
  request_json "${BASE_URL}/api/v1/atomicnebula/products/lookup$(build_query)"
}

stock_products() {
  lookup_products "$@" | jq 'if type == "array" then map({
    id: (.id // .productId // ._id),
    name,
    sku,
    availableQty,
    qtyOnHand,
    allocatedQty,
    reservedQty,
    stockUpdatedAt,
    stockAgeMins
  }) else . end'
}

price_products() {
  lookup_products "$@" | jq 'if type == "array" then map({
    id: (.id // .productId // ._id),
    name,
    sku,
    price,
    currency,
    billingFrequency,
    isRecurring
  }) else . end'
}

list_products() {
  query_params=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --search) add_query_param "search" "$2"; shift 2 ;;
      --category) add_query_param "category" "$2"; shift 2 ;;
      --is-recurring) add_query_param "isRecurring" "$2"; shift 2 ;;
      --billing-frequency) add_query_param "billingFrequency" "$2"; shift 2 ;;
      --pipeline-id) add_query_param "lifecyclePipelineId" "$2"; shift 2 ;;
      --stage-id) add_query_param "lifecycleStageId" "$2"; shift 2 ;;
      --sort-by) add_query_param "sortBy" "$2"; shift 2 ;;
      --sort-order) add_query_param "sortOrder" "$2"; shift 2 ;;
      --limit) add_query_param "limit" "$2"; shift 2 ;;
      --cursor) add_query_param "cursor" "$2"; shift 2 ;;
      --env) shift 2 ;;
      *) echo "Unknown list option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done

  request_json "${BASE_URL}/api/v1/atomicnebula/products$(build_query)"
}

get_product() {
  local product_id="${1:-}"
  if [[ -z "$product_id" ]]; then
    echo "Usage: an-products.sh get <productId>" >&2
    exit 2
  fi
  request_json "${BASE_URL}/api/v1/atomicnebula/products/$(urlencode "$product_id")"
}

case "${1:-}" in
  lookup) shift; lookup_products "$@" ;;
  stock) shift; stock_products "$@" ;;
  price) shift; price_products "$@" ;;
  list) shift; list_products "$@" ;;
  get) shift; get_product "$@" ;;
  *) usage >&2; exit 2 ;;
esac

#!/bin/sh
# Docker HEALTHCHECK probe for the xelis daemon — ported from the ethpow build
# tree (healthcheck.sh). Original semantics preserved:
#   1. the node answers get_block_template for our address (no RPC error),
#   2. a block template came back (node is mining-capable, not just synced),
#   3. the node is at least at the height of a reference/seed node,
#   4. the height changed since the previous probe (a stalled node is unhealthy).
# Made configurable instead of hardcoded, so the image is not tied to one
# deployment's address or one public seed node.
#
#   XELIS_RPC_PORT    local JSON-RPC port              (default 8079)
#   XELIS_ADDRESS     address used for the template    (default: mainnet test addr)
#   XELIS_SEED_NODE   reference node JSON-RPC URL      (default: https://node.xelis.io/json_rpc)
#   XELIS_SEED_TTL    seed-height cache TTL, seconds   (default 180)
#
# Exit 0 = healthy, non-zero = unhealthy (docker restarts/marks accordingly).
set -u

PREV_HEIGHT_FILE="/tmp/prev_height"
SEED_HEIGHT_FILE="/tmp/seed_height"
PORT="${XELIS_RPC_PORT:-8079}"
ENDPOINT="http://127.0.0.1:${PORT}/json_rpc"
ADDRESS="${XELIS_ADDRESS:-xel:mtcsaaz0p6482uzlpyejz5z8ks5wde3g06la3nms8vwhetat3dwsq99ely5}"
SEED_NODE="${XELIS_SEED_NODE:-https://node.xelis.io/json_rpc}"
SEED_HEIGHT_TTL="${XELIS_SEED_TTL:-180}"

fetch_seed_height() {
  response=$(curl --silent --show-error --fail --max-time 10 -X POST "$SEED_NODE" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"get_info","id":1}')
  if [ $? -ne 0 ]; then
    echo "Curl command failed: $response"
    return 1
  fi
  SEED_HEIGHT=$(echo "$response" | jq -r '.result.height')
  echo "$SEED_HEIGHT" > "$SEED_HEIGHT_FILE"
  return 0
}

need_refresh=0
if [ -e "$SEED_HEIGHT_FILE" ]; then
  file_age=$(( $(date +%s) - $(stat -c %Y "$SEED_HEIGHT_FILE") ))
  if [ "$file_age" -gt "$SEED_HEIGHT_TTL" ]; then
    need_refresh=1
  else
    SEED_HEIGHT=$(cat "$SEED_HEIGHT_FILE")
  fi
else
  need_refresh=1
fi

if [ "$need_refresh" -eq 1 ]; then
  if ! fetch_seed_height; then
    exit 1
  fi
fi

response=$(curl --silent --show-error --fail -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{
  "jsonrpc": "2.0",
  "method": "get_block_template",
  "id": 1,
  "params": {
    "address": "'"$ADDRESS"'"
  }
}')

if [ $? -ne 0 ]; then
  echo "Curl command failed: $response"
  exit 1
fi

error=$(echo "$response" | jq -r '.error.message')
if [ "$error" != "null" ]; then
  echo "Error in response: $error"
  exit 1
fi

current_height=$(echo "$response" | jq -r '.result.height')
template=$(echo "$response" | jq -r '.result.template')

# Startup gate: do not report healthy until we are at least at the seed height.
if [ "$current_height" -lt "$SEED_HEIGHT" ]; then
  exit 1
fi

if [ -n "$current_height" ] && [ "$current_height" -eq "$current_height" ] 2>/dev/null; then
  echo "Current Height: $current_height"
  echo "Current template: $template"

  if [ -f "$PREV_HEIGHT_FILE" ]; then
    prev_height=$(cat "$PREV_HEIGHT_FILE")
  else
    prev_height=""
  fi

  if [ -z "$prev_height" ]; then
    echo "$current_height" > "$PREV_HEIGHT_FILE"
    if [ -z "$template" ] || [ "$template" = "null" ]; then
      echo "Template is missing in the response."
      exit 1
    fi
    exit 0
  fi

  if [ "$current_height" -eq "$prev_height" ]; then
    echo "Height has not changed."
    exit 1
  else
    echo "$current_height" > "$PREV_HEIGHT_FILE"
    if [ -z "$template" ] || [ "$template" = "null" ]; then
      echo "Template is missing in the response."
      exit 1
    fi
    exit 0
  fi
else
  echo "Failed to get height"
  exit 1
fi

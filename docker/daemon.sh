#!/bin/bash
# Container-side JSON-RPC CLI for the xelis daemon — ported from the ethpow
# build tree (daemon.sh, which superseded rpc.sh by adding --debug). Method
# names map to their positional/object params; unknown methods fall through to
# a generic object built from the remaining arguments.
#
#   XELIS_RPC_URL  endpoint (default http://127.0.0.1:8079/json_rpc; the wallet
#                  RPC listens on 8080, so set it for wallet containers)
#
# Usage: daemon.sh [--raw|-r] [--debug|-d] <method> [<param1> <param2> ...]
set -u

HOST_ENDPOINT="${XELIS_RPC_URL:-http://127.0.0.1:8079/json_rpc}"

RAW_OUTPUT=false
DEBUG=false

while [[ "${1:-}" == "--raw" || "${1:-}" == "-r" || "${1:-}" == "--debug" || "${1:-}" == "-d" ]]; do
  case "$1" in
    --raw|-r)
      RAW_OUTPUT=true
      shift
      ;;
    --debug|-d)
      DEBUG=true
      shift
      ;;
  esac
done

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 [--raw|-r] [--debug|-d] <method> [<param1> <param2> ...]"
  exit 1
fi

METHOD=$1
shift

map_params() {
  local method=$1
  shift
  local params=""
  case $method in
    get_block_count)
      ;;
    on_get_block_hash)
      params="[$1]"
      ;;
    get_block_template)
      params="{\"address\":\"$1\"}"
      ;;
    submit_block)
      params="[$1]"
      ;;
    get_last_block_header)
      ;;
    get_block_header_by_hash)
      params="{\"hash\":\"$1\"}"
      ;;
    get_block_header_by_height)
      params="{\"height\":$1}"
      ;;
    get_block)
      params="{\"height\":$1}"
      ;;
    get_block_hash)
      params="[$1]"
      ;;
    get_block_headers_range)
      params="{\"start_height\":$1,\"end_height\":$2}"
      ;;
    get_block_by_hash)
      params="{\"hash\":\"$1\"}"
      ;;
    get_transaction)
      params="{\"tx_hash\":\"$1\"}"
      ;;
    get_transaction_pool)
      ;;
    get_info)
      ;;
    hard_fork_info)
      ;;
    validate_address)
      params="{\"address\":\"$1\",\"strict\":$2}"
      ;;
    get_tx_global_output_indexes)
      params="{\"tx_hash\":\"$1\"}"
      ;;
    get_random_outs)
      amounts="["
      for amount in ${1//,/ }; do
        amounts="${amounts}\"${amount}\","
      done
      amounts="${amounts%,}]"
      params="{\"amounts\":$amounts,\"count\":$2}"
      ;;
    get_transactions_by_heights)
      params="{\"heights\":[$1]}"
      ;;
    get_network_hashrate)
      ;;
    *)
      if [ "$#" -gt 0 ]; then
        params="{"
        for arg in "$@"; do
          params="$params\"$arg\","
        done
        params="${params%,}}"
      fi
      ;;
  esac
  echo $params
}

PARAMS=$(map_params $METHOD "$@")

if [ -n "$PARAMS" ]; then
  PAYLOAD="{\"jsonrpc\":\"2.0\",\"id\":\"0\",\"method\":\"$METHOD\",\"params\":$PARAMS}"
else
  PAYLOAD="{\"jsonrpc\":\"2.0\",\"id\":\"0\",\"method\":\"$METHOD\"}"
fi

if $DEBUG; then
  echo "Payload: $PAYLOAD"
fi

RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" --data "$PAYLOAD" "$HOST_ENDPOINT")

if $RAW_OUTPUT; then
  echo "$RESPONSE"
else
  echo "$RESPONSE" | jq .
fi

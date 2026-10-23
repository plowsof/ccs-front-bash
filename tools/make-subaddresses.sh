#!/usr/bin/env bash
# make-subaddresses.sh WALLET_RPC COUNT OUT [--testnet]: write the first COUNT subaddresses of
# account 0 of a wallet to OUT, one "index address" per line (index 0 is the main address).
# Asks for the wallet's main address and private view key (not echoed) and derives them in a
# view-only copy made in a temporary folder by an offline monero-wallet-rpc (WALLET_RPC, the
# binary): no spend key, no daemon, nothing written to the real wallet. The folder is removed
# at the end. Run it on the offline machine, then sign OUT with sign-subaddresses.sh.
set -euo pipefail
rpcbin=${1:?WALLET_RPC} count=${2:?COUNT} out=${3:?OUT} net=${4:-}
[[ $count =~ ^[1-9][0-9]*$ ]] || { echo "COUNT is not a number" >&2; exit 1; }
[[ -z $net || $net == --testnet || $net == --stagenet ]] || { echo "the 4th argument is --testnet or --stagenet" >&2; exit 1; }
read -rp "main address: " addr
read -rsp "private view key: " vk; echo
[[ $addr =~ ^[0-9A-Za-z]{95}$ && $vk =~ ^[0-9a-f]{64}$ ]] || { echo "not an address and a view key" >&2; exit 1; }

dir=$(mktemp -d); chmod 700 "$dir"
port=$((20000 + RANDOM % 20000))
"$rpcbin" $net --offline --wallet-dir "$dir" --rpc-bind-ip 127.0.0.1 --rpc-bind-port "$port" \
    --disable-rpc-login --non-interactive --log-file "$dir/rpc.log" > /dev/null 2>&1 &
pid=$!
trap 'kill "$pid" 2> /dev/null; wait "$pid" 2> /dev/null; rm -rf "$dir"' EXIT
rpc() { curl -s -m 600 "http://127.0.0.1:$port/json_rpc" -d "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"$1\",\"params\":$2}"; }
for _ in $(seq 60); do rpc get_version '{}' | grep -q '"result"' && break; sleep 1; done

# checked above to be base58 and hex, so safe in JSON as they are; sent on stdin (printf is
# a builtin), never in a command line other users could see
printf '{"jsonrpc":"2.0","id":0,"method":"generate_from_keys","params":{"filename":"viewonly","address":"%s","viewkey":"%s","password":"","restore_height":0}}' "$addr" "$vk" \
    | curl -s -m 60 "http://127.0.0.1:$port/json_rpc" -d @- \
    | jq -e .result > /dev/null || { echo "could not make the view-only wallet" >&2; exit 1; }
unset vk

have=1
while ((have < count)); do
    n=$((count - have < 64 ? count - have : 64))   # create_address makes at most 64 at a time
    rpc create_address "{\"account_index\":0,\"count\":$n}" | jq -e .result > /dev/null || { echo "create_address failed" >&2; exit 1; }
    have=$((have + n))
    ((have % 6400)) || echo "$have" >&2
done
rpc get_address '{"account_index":0}' | jq -r '.result.addresses | sort_by(.address_index)[] | "\(.address_index) \(.address)"' > "$out.tmp"
[[ $(wc -l < "$out.tmp") == "$count" && $(head -1 "$out.tmp") == "0 $addr" ]] || { echo "the list came out wrong" >&2; exit 1; }
mv "$out.tmp" "$out"
echo "wrote $count subaddresses to $out" >&2

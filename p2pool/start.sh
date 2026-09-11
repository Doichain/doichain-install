#!/usr/bin/env bash
set -euo pipefail

# Build the merged-mining URL at RUNTIME. The Dockerfile's `ENV MERGED_MINGIN_URL`
# interpolates DOICHAIN_RPC_* at *build* time, so overriding those in compose had
# no effect on the baked-in value.
: "${DOICHAIN_RPC_USER:=admin}"
: "${DOICHAIN_RPC_PASSWORD:=password}"
: "${DOICHAIN_RPC_HOST:=doichain}"
: "${DOICHAIN_RPC_PORT:=8339}"
MERGED_MINGIN_URL="http://${DOICHAIN_RPC_USER}:${DOICHAIN_RPC_PASSWORD}@${DOICHAIN_RPC_HOST}:${DOICHAIN_RPC_PORT}"

echo "merged mining url      : http://${DOICHAIN_RPC_USER}:***@${DOICHAIN_RPC_HOST}:${DOICHAIN_RPC_PORT}"
echo "Doichain payout address: ${P2POOL_DOICHAIN_DEFAULT_ADDR}"
echo "Bitcoin payout address : ${P2POOL_BITCOIN_DEFAULT_ADDR}"

# exec (was: `nohup ... &` followed by `exec /bin/bash`) so p2pool is PID 1 --
# otherwise a p2pool crash leaves the container "up" running only bash.
exec /usr/bin/pypy /usr/src/p2pool/run_p2pool.py \
	--net bitcoin \
	--bitcoind-address "${BITCOIND_ADDRESS:-bitcoin}" \
	--merged_addr "${MERGED_MINGIN_URL}/?payout=${P2POOL_DOICHAIN_DEFAULT_ADDR}" \
	-a "${P2POOL_BITCOIN_DEFAULT_ADDR}" \
	-n p2pool.org \
	--give-author=0

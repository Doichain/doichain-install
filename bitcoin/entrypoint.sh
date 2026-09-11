#!/bin/bash
set -euo pipefail

_RPC_PORT=${RPC_PORT}
_NODE_PORT=${NODE_PORT}

if [ $REGTEST = true ]; then
	_RPC_PORT=$RPC_PORT_REGTEST
  _NODE_PORT=$NODE_PORT_REGTEST
fi

if [ $TESTNET = true ]; then
	_RPC_PORT=$RPC_PORT_TESTNET
  	_NODE_PORT=$NODE_PORT_TESTNET
fi

if [ -z ${RPC_USER} ]; then
	RPC_USER='admin'
	echo "RPC_USER was not set, using "$RPC_USER
fi

if [ -z ${RPC_PASSWORD} ]; then
	#echo "generating password"
	RPC_PASSWORD=$(openssl rand -hex 30)
	echo "RPC_PASSWORD was not set, generated: "$RPC_PASSWORD
fi
echo "loooks good!"
BITCOIN_CONF_FILE=/home/bitcoin/data/bitcoin/bitcoin.conf
if [ ! -f "$BITCOIN_CONF_FILE" ]; then
    echo "BITCOIN_CONF_FILE not found - generating new!"
	echo "
	daemon=1
	server=1
	rpcuser=${RPC_USER}
	rpcpassword=${RPC_PASSWORD}
	rpcallowip=${RPC_ALLOW_IP}
	rpcbind=0.0.0.0
	rpcport=${_RPC_PORT}
	prune=1000
	port=${_NODE_PORT}" > $BITCOIN_CONF_FILE
fi

CHAIN_DATA=/home/bitcoin/data/bitcoin/chainstate/CURRENT
echo "checking if pruned bitcoin blockchain exists $CHAIN_DATA"
if [ ! -f "$CHAIN_DATA" ]; then
    cd /home/bitcoin/data/bitcoin
    echo "downloading pruned bitcoin blockchain from doi.works"
	curl -fL --retry 5 --retry-delay 5 -C - https://www.doi.works/pruned/bitcoin-pruned.tgz --output bitcoin-pruned.tgz
	# snapshot entries are prefixed with ".bitcoin/" -> strip that component so
	# blocks/ and chainstate/ land directly in the datadir bitcoind actually reads
	tar --strip-components=1 --exclude='bitcoin.conf' --exclude='bitcoind.pid' --exclude='debug.log' -xzf bitcoin-pruned.tgz
	rm bitcoin-pruned.tgz
    # '*' misses dotfiles, and chown fails when not running as root -> don't abort
    chown -R bitcoin:bitcoin . 2>/dev/null || true
    cd /home/bitcoin
fi

exec "$@"
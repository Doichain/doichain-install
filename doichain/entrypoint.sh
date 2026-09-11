#!/bin/bash
set -euo pipefail

_RPC_PORT=${RPC_PORT}
_NODE_PORT=${NODE_PORT}
_DAPP_URL=${DAPP_URL}
_REGTEST=0
_TESTNET=0

if [ $REGTEST = true ]; then
	_REGTEST=1
	_RPC_PORT=$RPC_PORT_REGTEST
  	_NODE_PORT=$NODE_PORT_REGTEST
fi

if [ $TESTNET = true ]; then
	_TESTNET=1
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

if [ -z ${DAPP_URL} ]; then
	_DAPP_URL=$DAPP_URL
fi

# NOTE: everything between the quotes below is written verbatim into the conf --
# keep backticks and double quotes OUT of it, or the shell breaks the string.
#
# Why the conf sets an explicit bind= :
# Doichain's P2P (8338) and RPC (8339) ports are adjacent, and Core derives the
# onion service target as P2P+1, i.e. exactly the RPC port. That target is pushed
# into onion_binds unconditionally -- in init.cpp the push happens *before* the
# if (listenonion) check -- so the P2P listener tries to bind 127.0.0.1:8339,
# collides with the already-bound RPC, and the node dies with 'Failed to listen
# on any port'. Setting -listenonion=0 does NOT help: it only skips
# StartTorControl. An explicit bind makes init derive the onion target from
# vBinds instead, so nothing extra is bound.
# NOTE: testnet has the same collision (18338/18339) and needs the same fix.
DOICHAIN_CONF_FILE=/home/doichain/data/doichain/doichain.conf
mkdir -p "$(dirname "$DOICHAIN_CONF_FILE")"
if [ ! -f "$DOICHAIN_CONF_FILE" ]; then
echo "DOICHAIN_CONF_FILE not found - generating new!"
echo "
regtest=$_REGTEST
testnet=$_TESTNET
server=1
bind=0.0.0.0:8338
listenonion=0
wallet=1
rpcuser=${RPC_USER}
rpcpassword=${RPC_PASSWORD}
rpcbind=0.0.0.0
rpcallowip=${RPC_ALLOW_IP}
txindex=1
fallbackfee=0.0002
namehistory=1
rpcworkqueue=100
blocknotify=curl -X GET ${DAPP_URL}/api/v1/blocknotify?block=%s
walletnotify=curl -X GET ${DAPP_URL}/api/v1/walletnotify?tx=%s

[test]
rpcport=${_RPC_PORT}
rpcbind=0.0.0.0
rpcallowip=0.0.0.0/0
wallet=1
port=${_NODE_PORT}

[regtest]
rpcport=${_RPC_PORT}
rpcbind=0.0.0.0
rpcallowip=0.0.0.0/0
wallet=1
port=${_NODE_PORT}" > $DOICHAIN_CONF_FILE
fi

exec "$@"

#!/usr/bin/env bash
_REGTEST=''
if [ "$REGTEST" = true ]; then
	_REGTEST='-regtest -addnode='$CONNECTION_NODE
fi

_TESTNET=''
if [ "$TESTNET" = true ]; then
	_TESTNET='-testnet -addnode='$CONNECTION_NODE
fi

# -daemon=0 explicitly: in a container the process must stay in the foreground.
# Passed on the command line (not just dropped from the generated conf) so that
# deployments whose bitcoin.conf already contains `daemon=1` are overridden too --
# the conf is only regenerated when missing.
#
# exec so bitcoind becomes PID 1 -> crashes actually stop the container (restart
# policies fire) and `docker stop` shuts bitcoind down cleanly instead of killing
# a wrapping bash, which risks chainstate corruption.
exec bitcoind -daemon=0 $_REGTEST $_TESTNET ${BITCOIN_EXTRA_ARGS:-}

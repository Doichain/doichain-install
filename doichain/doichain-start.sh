#!/usr/bin/env bash
_REGTEST=''
if [ "$REGTEST" = true ]; then
	_REGTEST='-regtest -addnode='$CONNECTION_NODE
fi

_TESTNET=''
if [ "$TESTNET" = true ]; then
	_TESTNET='-testnet -addnode='$CONNECTION_NODE
fi

# -datadir MUST point at the directory the entrypoint wrote doichain.conf into,
# which is also on the mounted volume. Without it doichaind falls back to
# $HOME/.doichain *inside the container*: the generated conf is ignored and the
# whole chain is lost on every container recreate.
#
# exec so doichaind becomes PID 1 -> a crash actually stops the container (so
# restart policies fire) and `docker stop` signals doichaind for a clean shutdown
# instead of signalling a wrapping bash.
exec doichaind -datadir=/home/doichain/data/doichain $_REGTEST $_TESTNET ${DOICHAIN_EXTRA_ARGS:-}

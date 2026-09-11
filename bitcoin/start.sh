#!/bin/bash
set -euo pipefail

# exec (was: backgrounded with `&` plus `exec /bin/bash`) so bitcoind ends up as
# PID 1. Previously a bitcoind crash left the container "up" running only bash.
exec /home/bitcoin/scripts/bitcoin-start.sh

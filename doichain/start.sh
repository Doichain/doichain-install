#!/bin/bash
set -euo pipefail

# exec (was: backgrounded with `&` plus `exec /bin/bash`) so doichaind ends up as
# PID 1. Previously a doichaind crash left the container "up" running only bash.
exec scripts/doichain-start.sh

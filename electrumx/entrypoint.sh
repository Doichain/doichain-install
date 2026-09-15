#!/bin/sh
set -eu

# DAEMON_URL must name the RPC port explicitly: the Doichain coin class still
# defaults to 8338, which in Core 31 is the P2P port -- a URL without a port
# connects to the wrong socket and ElectrumX never gets an answer.
: "${DAEMON_URL:?DAEMON_URL is required, e.g. http://admin:<password>@doichain:8339/}"
case "$DAEMON_URL" in
  *:8339*|*:18339*|*:18332*) ;;
  *) echo "DAEMON_URL has no explicit RPC port (8339 on mainnet) -- refusing to start" >&2; exit 1 ;;
esac

# ElectrumX serves SSL/WSS only with a certificate. Generate a self-signed one
# on first start; replace it with a real certificate by mounting one at
# SSL_CERTFILE/SSL_KEYFILE.
if [ -n "${SSL_CERTFILE:-}" ] && [ ! -f "$SSL_CERTFILE" ]; then
  mkdir -p "$(dirname "$SSL_CERTFILE")"
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj "/CN=${REPORT_HOST:-electrumx}" \
    -keyout "$SSL_KEYFILE" -out "$SSL_CERTFILE" 2>/dev/null
  echo "generated a self-signed certificate at $SSL_CERTFILE"
fi

exec "$@"

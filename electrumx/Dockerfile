# ElectrumX for Doichain: Doichain/electrumx (ElectrumX 1.15.0 plus the Doichain
# coin class -- AuxPoW + SegWit deserializer, name index including name_doi).
# This is the code the fleet's ElectrumX servers run against Doichain Core
# v31.1.5.
#
# The source comes from the named build context "electrumx-src", pinned to a
# commit in docker-compose-mining.yml. To build from a local checkout:
#   docker build --build-context electrumx-src=../electrumx \
#     --build-arg ELECTRUMX_REF=$(git -C ../electrumx rev-parse HEAD) \
#     -t doichain/electrumx:v1.15.0-doi1 electrumx/
FROM python:3.9-slim-bookworm

ARG ELECTRUMX_REF=unknown

# plyvel needs a compiler and the LevelDB headers at install time, only the
# library at runtime. aiorpcX is pinned below 0.19 as setup.py demands.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential libleveldb-dev libleveldb1d openssl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=electrumx-src . /src
RUN pip install --no-cache-dir 'aiorpcX[ws]>=0.18.3,<0.19' attrs plyvel pylru 'aiohttp>=3.3,<4' \
    && pip install --no-cache-dir /src \
    && echo "$ELECTRUMX_REF" > /electrumx-source-commit \
    && rm -rf /src \
    && apt-get purge -y build-essential libleveldb-dev && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 1000 electrumx && mkdir -p /data && chown electrumx /data
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

# Defaults for the compose stack; DAEMON_URL has none on purpose (entrypoint).
# rpc:// is the admin interface (docker exec electrumx electrumx_rpc getinfo); it
# listens on localhost:8000 inside the container only.
# COST_SOFT_LIMIT / COST_HARD_LIMIT deliberately keep ElectrumX's defaults
# (1,000 / 10,000): they throttle, and finally disconnect, a client that keeps
# the server busy. Setting both to 0 switches that protection off entirely.
ENV COIN=Doichain \
    NET=mainnet \
    DB_DIRECTORY=/data \
    SERVICES=tcp://:50001,ssl://:50002,wss://:50004,rpc:// \
    SSL_CERTFILE=/data/ssl/server.crt \
    SSL_KEYFILE=/data/ssl/server.key \
    PEER_DISCOVERY=off

USER electrumx
VOLUME /data
EXPOSE 50001 50002 50004
ENTRYPOINT ["/entrypoint.sh"]
CMD ["electrumx_server"]

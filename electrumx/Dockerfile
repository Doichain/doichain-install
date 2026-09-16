# ElectrumX 2.0.0 for Doichain: Doichain/electrumx (upstream 2.0.0 plus the
# Doichain coin classes -- AuxPoW + SegWit deserializer, name index including
# name_doi). Replaces the 1.15.0 image, which ran on a Python that is past end
# of life and pinned aiorpcX below 0.19.
#
# Two stages, following upstream's own contrib/Dockerfile: the RocksDB bindings
# need a compiler and headers to build, but only the shared library to run.
#
# The source comes from the named build context "electrumx-src", pinned to a
# commit in docker-compose-mining.yml. To build from a local checkout:
#   docker build --build-context electrumx-src=../electrumx \
#     --build-arg ELECTRUMX_REF=$(git -C ../electrumx rev-parse HEAD) \
#     -t doichain/electrumx:v2.0.0-doi1 electrumx/

FROM python:3.14-trixie AS builder

WORKDIR /usr/src/app

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential librocksdb-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

# The project is named "e-x" since 2.0; the [rocksdb] extra pulls rocksdb-ng.
COPY --from=electrumx-src . /src
RUN python -m venv venv \
    && venv/bin/pip install --no-cache-dir '/src[rocksdb]' \
    && rm -rf /src


FROM python:3.14-slim-trixie

ARG ELECTRUMX_REF=unknown

# RocksDB at runtime only (no headers, no compiler); openssl for the self-signed
# certificate the entrypoint generates on first start.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      librocksdb9.10 openssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app
COPY --from=builder /usr/src/app .
RUN echo "$ELECTRUMX_REF" > /electrumx-source-commit
ENV PATH="/usr/src/app/venv/bin:$PATH"

RUN useradd --create-home --uid 1000 electrumx && mkdir -p /data && chown electrumx /data
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

# Defaults for the compose stack; DAEMON_URL has none on purpose (entrypoint).
# rpc:// is the admin interface (docker exec electrumx electrumx_rpc getinfo); it
# listens on localhost:8000 inside the container only.
#
# DB_ENGINE is mandatory since 2.0. RocksDB syncs roughly 25 % faster than
# LevelDB on an SSD. 2.0 changed the on-disk schema with no migration path, so a
# server coming from the 1.15 image has to start from an empty DB_DIRECTORY
# either way -- on this chain that took about 25 minutes from empty volumes.
#
# COST_SOFT_LIMIT / COST_HARD_LIMIT deliberately keep ElectrumX's defaults
# (1,000 / 10,000): they throttle, and finally disconnect, a client that keeps
# the server busy. Setting both to 0 switches that protection off entirely.
ENV COIN=Doichain \
    NET=mainnet \
    DB_ENGINE=rocksdb \
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

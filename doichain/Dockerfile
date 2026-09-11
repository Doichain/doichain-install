# Doichain Core 31.1 — nc31.1 / Bitcoin Core 31 base, built with CMake.
# (Replaces the old 0.20-era autotools + BerkeleyDB 4.8 build.)
# Pin the source at build time:  --build-arg DOICHAIN_VER=v31.1.1
FROM debian:12

ARG DOICHAIN_VER=feat/digishield-daa
ENV DOICHAIN_VER=$DOICHAIN_VER

# Runtime / start-script vars (ports match Core 31: P2P 8338, RPC 8339)
ENV CONFIRM_ADDRESS="" \
    CONNECTION_NODE=116.203.34.154 \
    DAPP_URL=http://localhost:3000 \
    NODE_PORT=8338 NODE_PORT_TESTNET=18338 NODE_PORT_REGTEST=18445 \
    REGTEST=false TESTNET=false \
    RPC_ALLOW_IP=172.17.0.0/16 RPC_PASSWORD="" \
    RPC_PORT=8339 RPC_PORT_TESTNET=18339 RPC_PORT_REGTEST=18332 \
    RPC_USER=admin

# Build + runtime dependencies for Core 31 (CMake, C++20, libevent, SQLite).
# No BerkeleyDB: Core 31 dropped legacy BDB wallets; wallets are SQLite (descriptor).
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential cmake pkg-config git ca-certificates python3 \
      libevent-dev libboost-dev libsqlite3-dev \
      curl jq bc dos2unix locales sudo \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en

RUN adduser --disabled-password --gecos '' doichain && \
    adduser doichain sudo && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
USER doichain

# Build Doichain Core with CMake (GUI/IPC/tests/bench/ZMQ off, SQLite wallet on),
# install doichaind + doichain-cli, then drop the build tree to keep the image small.
WORKDIR /home/doichain
RUN git clone --branch "$DOICHAIN_VER" --depth 1 https://github.com/Doichain/doichain-core.git && \
    cd doichain-core && \
    cmake -B build -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_GUI=OFF -DENABLE_IPC=OFF -DBUILD_TESTS=OFF -DBUILD_BENCH=OFF \
      -DWITH_ZMQ=OFF -DENABLE_WALLET=ON && \
    cmake --build build -j"$(nproc)" --target doichaind doichain-cli && \
    sudo install -m0755 build/bin/doichaind build/bin/doichain-cli /usr/local/bin/ && \
    doichaind --version | head -1 && \
    cd /home/doichain && sudo rm -rf doichain-core/build

# Start scripts
WORKDIR /home/doichain/scripts/
COPY entrypoint.sh entrypoint.sh
COPY start.sh start.sh
COPY getblocktimes.sh getblocktimes.sh
COPY doichain-start.sh doichain-start.sh
RUN sudo dos2unix entrypoint.sh start.sh doichain-start.sh && \
    sudo chmod +x entrypoint.sh start.sh doichain-start.sh getblocktimes.sh

# Data dir: ~/.doichain -> persisted volume at /home/doichain/data/doichain
WORKDIR /home/doichain
RUN mkdir -p data/doichain && ln -s /home/doichain/data/doichain /home/doichain/.doichain

WORKDIR /home/doichain
ENTRYPOINT ["scripts/entrypoint.sh"]
CMD ["scripts/start.sh"]

EXPOSE 8338 8339 18338 18339

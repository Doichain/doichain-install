# Doichain environment via Docker Compose

Compose files, Dockerfiles and images to run a Doichain environment: a Doichain
Core node on its own, merge mining with p2pool, an ElectrumX server for Electrum
wallets, and the Doichain dApp for email Double Opt-In.

All nodes here run **Doichain Core 31.1**, the rules the network has followed
since the DigiShield fork at block 431,017.

## Which stack do you want?

| Compose file | What it starts | Use it for |
|---|---|---|
| `docker-compose-mining.yml` | bitcoind (pruned), Doichain Core, p2pool, ElectrumX | merge mining DOI + BTC, and serving Electrum wallets |
| `docker-compose-email-doi-mainnet.yml` | nginx + certbot, Doichain Core, dApp, MongoDB | running a Double Opt-In server on mainnet |
| `docker-compose-email-doi-testnet.yml` | the same, on testnet | trying the dApp without real coins |

## Prerequisites

- **Docker Engine** 20.10 or newer
- **Docker Compose v2** (`docker compose`, not `docker-compose`), **2.17 or
  newer** — the ElectrumX service uses `additional_contexts`

## Mining stack

```bash
cp .env.mining.example .env
```

Then edit `.env`:

| Variable | Meaning |
|---|---|
| `P2POOL_DOICHAIN_DEFAULT_ADDR` | where p2pool pays out your DOI |
| `P2POOL_BITCOIN_DEFAULT_ADDR` | where p2pool pays out your BTC |
| `DOICHAIN_RPC_PASSWORD` | required; `openssl rand -hex 32` |
| `BITCOIN_RPC_PASSWORD` | required; `openssl rand -hex 32` |
| `EXTERNAL_IP` | this host's public address, or the node stays invisible |

Compose refuses to start while the two passwords are empty. They are written
into `doichain.conf` / `bitcoin.conf` on the **first** start only.

```bash
docker compose -f docker-compose-mining.yml up -d      # start
docker compose -f docker-compose-mining.yml logs -f    # watch
docker compose -f docker-compose-mining.yml down       # stop
```

On the first start, `bitcoin-init` downloads a pruned Bitcoin snapshot (~11 GB,
about 25 GB free space needed during bootstrap). Until it is done, p2pool logs
that it cannot reach the Bitcoin RPC — that is expected, not a fault.

Details, open points and the reasoning: **[docs/stack-31.1.md](docs/stack-31.1.md)**.

## Double Opt-In server

```bash
cp .env.email-doi.example .env
```

Then edit `.env`: `SERVER_NAME` (the public name, e.g. `doichain.example.com`),
`RPC_USER`, `RPC_PASSWORD` (**change it**), and the `DAPP_SMTP_*` settings of the
mail server that sends the confirmation mails.

```bash
docker compose -f docker-compose-email-doi-mainnet.yml up -d
./init-letsencrypt.sh        # replace the self-signed certificate
docker compose -f docker-compose-email-doi-mainnet.yml down
```

Use `docker-compose-email-doi-testnet.yml` for testnet; the dApp is on port 4000
there instead of 3000.

> **Upgrading an existing Opt-In install:** these stacks ran
> `doichain/core:dc0.20.1.13` until September 2026, which follows the abandoned
> 0.20.x branch. A volume from that era carries both that chain's data and a
> BerkeleyDB wallet, and **Core 31 cannot load a BerkeleyDB wallet** — the dApp
> will come up without one. Either start from an empty `doichain-volume`, or
> migrate the wallet with `doichain-cli migratewallet` before pointing the dApp
> at it.

The dApp's JSON-RPC API is documented in the
[dApp repository](https://github.com/Doichain/dapp/blob/master/doc/en/json-rpc-api.md):
[authentication](https://github.com/Doichain/dapp/blob/master/doc/en/json-rpc-api.md#authentication),
[requesting a DOI](https://github.com/Doichain/dapp/blob/master/doc/en/json-rpc-api.md#create-opt-in),
[adding a user or project](https://github.com/Doichain/dapp/blob/master/doc/en/json-rpc-api.md#create-user).

## Ports

Published on the host:

| Port | Service | Stack |
|---|---|---|
| 8333 | Bitcoin P2P | mining |
| 8338 | Doichain P2P | mining |
| 9332 | p2pool | mining |
| 50001 / 50002 / 50004 | ElectrumX TCP / SSL / WSS | mining |
| 80, 443 | nginx | Opt-In |
| 3000 (testnet: 4000) | dApp | Opt-In |

**Deliberately not published:** the Doichain RPC (8339), the Bitcoin RPC (8332)
and MongoDB. They are reachable inside the compose network only — a published
RPC means an open door to a node with a wallet behind it.

## Is it working?

```bash
# node: chain tip, and that it is on the DigiShield chain
docker compose -f docker-compose-mining.yml exec doichain \
  doichain-cli -datadir=/home/doichain/data/doichain getblockchaininfo
docker compose -f docker-compose-mining.yml exec doichain \
  doichain-cli -datadir=/home/doichain/data/doichain getblockhash 431018
#   -> 71d50ff12b090561cc918ddb560334b4350758c7eace3f058dd332fb112f4b67

# ElectrumX: index height against node height
docker exec electrumx electrumx_rpc getinfo

# p2pool: is it merge mining?
docker compose -f docker-compose-mining.yml logs -f p2pool
```

From empty volumes the node had every block after about 20 minutes and the
ElectrumX index was complete two minutes later, measured on Docker Desktop.

## Everyday commands

```bash
docker compose -f <compose-file> ps            # what is running
docker compose -f <compose-file> logs -f <service>
docker compose -f <compose-file> exec <service> bash
```

Inside the Doichain container, `doichain-cli` needs the datadir:

```bash
doichain-cli -datadir=/home/doichain/data/doichain getblockchaininfo
doichain-cli -datadir=/home/doichain/data/doichain getpeerinfo
doichain-cli -datadir=/home/doichain/data/doichain getbalance
```

There are also convenience scripts in the repository root: `start-mining.sh`,
`start-email-doi-mainnet.sh`, `start-email-doi-testnet.sh`, `stop.sh` and
`deleteEverything.sh` (which removes containers **and volumes** — it deletes the
chain data).

## Documentation

- **[docs/stack-31.1.md](docs/stack-31.1.md)** — the current stack: images,
  ElectrumX, open points.
- [docs/history-2026-09.md](docs/history-2026-09.md) — the relaunch work log of
  September 2026; superseded, kept for the reasoning behind the decisions.
- [TODO.md](TODO.md) — open items on the dApp and testnet side.
- `contrib/nbits-audit.py` — finds blocks whose difficulty does not follow the
  consensus rule.

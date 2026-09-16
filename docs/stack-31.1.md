# The Doichain 31.1 stack

What `docker-compose-mining.yml` starts today, and what to watch for. For the
work log of the September 2026 relaunch see
[history-2026-09.md](history-2026-09.md).

Goal: run the new Doichain Core **31.1** (nc31.1 / Bitcoin Core 31 base, with the
DigiShield fast-DAA hard fork) together with p2pool and ElectrumX on a fresh
host, instead of the legacy 0.20 images this repo shipped.

## Status 2026-09-13: v31.1.5

- **Doichain Core v31.1.5 is released**: signed tag on `doichain-core`, a GitHub
  release with static Linux binaries, and **`doichain/core:v31.1.5` on Docker
  Hub** (also `latest`). The compose file **pulls** that image; nothing is built
  from source any more.
- **Fresh nodes join on their own.** v31.1.4 ships fixed seeds that all follow
  DigiShield, `dnsseed.doichain.org` hands out DigiShield nodes, and v31.1.5 fixed
  the last header-sync bug: a node with an empty datadir had all headers after
  120 s and every block after 240 s on a Linux server. This compose stack, from
  empty volumes on a desktop Mac: headers at the tip after ~8 minutes, every block
  after ~22 minutes, same tip hash as our nodes. No `-addnode` list needed.
- **p2pool merge-mines against v31.1.5 unchanged**: `createauxblock` on a v31.1.5
  node returns exactly the fields p2pool consumes (`hash`, `chainid`, `bits`,
  `coinbasevalue`, `_target`, `height`, `previousblockhash`). Checked from inside
  the compose network with p2pool's own RPC client and the URL `start.sh` builds;
  the AuxPoW functional tests pass on v31.1.5.
- **ElectrumX is a new service**, see below.
- **RPC is no longer exposed.** This file used to publish 8339 (doichaind, with a
  wallet behind it) and 8332 (bitcoind) on all interfaces, with the password
  `password` and `rpcallowip=0.0.0.0/0`. Both now stay on the compose network,
  and both passwords are required in `.env`.

## Run

```bash
git clone -b feat/doichain-31.1 https://github.com/Doichain/doichain-install.git
cd doichain-install
cp .env.mining.example .env
# set your payout addresses and both RPC passwords (openssl rand -hex 32)
docker compose -f docker-compose-mining.yml up -d
```

Ports facing the outside: `8338` (Doichain P2P), `8333` (Bitcoin P2P), `9332`
(p2pool), `50001`/`50002`/`50004` (ElectrumX TCP/SSL/WSS). Set `EXTERNAL_IP` to
the host's public address, or the node never advertises itself.

The RPC passwords are written into `doichain.conf` / `bitcoin.conf` on the
**first** start only. A host that already has volumes from an older version keeps
its old conf -- including an old `rpcallowip=0.0.0.0/0` -- until you edit it
there.

## ElectrumX

Service `electrumx`, image `doichain/electrumx:v2.0.0-doi1`, built from
`Doichain/electrumx` at the signed tag **`v2.0.0-doi1`** (commit `11877d7b`) --
upstream **ElectrumX 2.0.0** with the Doichain coin classes: AuxPoW + SegWit
deserializer, name index including `name_doi`. The compose file pins the commit
rather than the tag name, because a tag can be moved and a commit cannot.

- It trusts `doichaind` and does no consensus validation of its own, so the fork
  needs no change in ElectrumX.
- **Coming from the 1.15 image, the database has to be rebuilt.** 2.0 changed the
  on-disk schema and ships no migration path, so `electrumx-db` must start empty.
  On this chain that is cheap. Measured with this image from empty volumes on
  Docker Desktop: headers after ~7 min, every block after ~20 min, **index
  complete after ~22 min**, 0 errors, and the tip hash identical to a fleet
  node's at the same height.
- **The name index becomes usable.** 1.15.0 has no name RPC at all -- it has no
  `NameIndexElectrumX` session class, so our servers built the index and no
  client could read it. In 2.0 the coin class carries
  `SESSIONCLS = NameIndexAuxPoWElectrumX`, which registers
  `blockchain.name.get_value_proof`. Verified against the `name_doi` in block
  431,320: name history one entry, and the full proof (height, raw transaction,
  merkle path). The handler is only registered once a session negotiates
  **protocol ≥ 1.4.3**; at plain `1.4` the server answers "unknown method".
- `DB_ENGINE` is mandatory since 2.0; the image sets `rocksdb`, which syncs
  roughly 25 % faster than LevelDB on an SSD.
- **Electrum wallets are unaffected**: 2.0 still serves `PROTOCOL_MIN = (1, 4)`,
  and Electrum-DOI speaks 1.4.
- `DAEMON_URL` carries the port `:8339`. The coin class now defaults to 8339
  itself, but the entrypoint still refuses a URL without an explicit port, so a
  hand-written one cannot reach the P2P socket (8338) unnoticed.
- Index status: `docker exec electrumx electrumx_rpc getinfo` (`db height` against
  `daemon height`). The admin RPC listens on localhost inside the container only.
- SSL and WSS use a self-signed certificate generated on first start; mount a real
  one at `SSL_CERTFILE` / `SSL_KEYFILE` for public use.
- `Doichain/electrumx` is **public** since 2026-09-16, so `docker compose build`
  works on any host. Compose still pulls `doichain/electrumx:v2.0.0-doi1` from
  Docker Hub first and falls back to the `build:` section only when the pull
  fails.
- The session cost limits (`COST_SOFT_LIMIT` / `COST_HARD_LIMIT`) keep ElectrumX's
  defaults, which throttle and then disconnect a client that keeps the server
  busy. Do not set them to 0 on a public server: that turns the protection off.

## Open issues

- [ ] The generated `doichain.conf` still sets `rpcallowip=0.0.0.0/0` in its
  `[test]` and `[regtest]` sections (the image's entrypoint writes them). Mainnet
  uses the compose subnet, and no RPC port is published on any network.
- [x] ElectrumX runtime age: the coin classes are ported to upstream 2.0.0
  (Doichain/electrumx#10), the image runs Python 3.14 with aiorpcX 0.25, and the
  yearly "DB::flush_count overflow" compaction is gone with the new schema.

- [ ] `doichain/bitcoind:v0.20.0` on Docker Hub still carries the dead
  `prunednode.today` URL; the `bitcoin-init` service works around it.
  Republishing it, and choosing a modern bitcoind (#1), is open.
- [ ] `doichain/p2pool:v34.0` on Docker Hub (2022) predates the fixed `start.sh`;
  the compose file mounts the repository's version over it. Republishing the
  image would make the mount unnecessary.
- [ ] `UA_NAME` is still `"Satoshi"` (the node advertises `/Satoshi:31.1.5/`).
- [x] ElectrumX: `TX_COUNT` / `TX_PER_BLOCK` carry real values since the 2.0 port
  (2,742,220 at height 431,763, from `getchaintxstats`). `PEERS` stays empty on
  purpose -- the servers neither announce nor discover each other.
- [x] Peer discovery for fresh nodes: fixed seeds (v31.1.4), header sync (v31.1.5),
  DNS seeder.
- [x] `wallet=1` in the generated conf: dropped.
- [x] Publish `doichain/core`: `v31.1.5` on Docker Hub.
- [x] ElectrumX service: added.
- [x] Testnet port collision: the generated `bind=` uses the active network's port.

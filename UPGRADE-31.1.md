# Upgrade to Doichain Core 31.1 (branch `feat/doichain-31.1`)

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

Service `electrumx`, image `doichain/electrumx:v1.15.0-doi1`, built from
`Doichain/electrumx` @ `94d10907` (ElectrumX 1.15.0 with the Doichain coin
class: AuxPoW + SegWit deserializer, name index including `name_doi`). It is the
code the fleet's ElectrumX servers run: the package installed on the canary
hashes identically, and there it indexes v31.1.5 live, database height equal to
node height, including a `name_doi` in block 431,320.

- It trusts `doichaind` and does no consensus validation of its own, so the fork
  needs no change in ElectrumX.
- `DAEMON_URL` must carry the port `:8339`: the coin class still defaults to 8338,
  which is the P2P port. The entrypoint refuses to start without it.
- It indexes while `doichaind` syncs. From empty volumes, the node had every
  block after ~22 minutes and the index was complete two minutes later (Docker
  Desktop on a Mac). Clients see the server once it has caught up.
- Index status: `docker exec electrumx electrumx_rpc getinfo` (`db height` against
  `daemon height`). The admin RPC listens on localhost inside the container only.
- SSL and WSS use a self-signed certificate generated on first start; mount a real
  one at `SSL_CERTFILE` / `SSL_KEYFILE` for public use.
- `Doichain/electrumx` is a private repository. Compose pulls
  `doichain/electrumx:v1.15.0-doi1` from Docker Hub first and falls back to the
  `build:` section only when the pull fails -- and that build needs access to the
  repository.
- The session cost limits (`COST_SOFT_LIMIT` / `COST_HARD_LIMIT`) keep ElectrumX's
  defaults, which throttle and then disconnect a client that keeps the server
  busy. Do not set them to 0 on a public server: that turns the protection off.

## Open issues

- [ ] The generated `doichain.conf` still sets `rpcallowip=0.0.0.0/0` in its
  `[test]` and `[regtest]` sections (the image's entrypoint writes them). Mainnet
  uses the compose subnet, and no RPC port is published on any network.
- [ ] ElectrumX 1.15.0 pins aiorpcX below 0.19, and the image runs it on Python
  3.9, which is past end of life. A maintained ElectrumX needs the Doichain coin
  class ported forward.

- [ ] `doichain/bitcoind:v0.20.0` on Docker Hub still carries the dead
  `prunednode.today` URL; the `bitcoin-init` service works around it.
  Republishing it, and choosing a modern bitcoind (#1), is open.
- [ ] `doichain/p2pool:v34.0` on Docker Hub (2022) predates the fixed `start.sh`;
  the compose file mounts the repository's version over it. Republishing the
  image would make the mount unnecessary.
- [ ] `UA_NAME` is still `"Satoshi"` (the node advertises `/Satoshi:31.1.5/`).
- [ ] ElectrumX: `TX_COUNT` / `TX_PER_BLOCK` are placeholders and `PEERS` is empty
  (#2); harmless for indexing.
- [x] Peer discovery for fresh nodes: fixed seeds (v31.1.4), header sync (v31.1.5),
  DNS seeder.
- [x] `wallet=1` in the generated conf: dropped.
- [x] Publish `doichain/core`: `v31.1.5` on Docker Hub.
- [x] ElectrumX service: added.
- [x] Testnet port collision: the generated `bind=` uses the active network's port.

---

# History (2026-09-11)

The sections below record the relaunch as it happened. Version numbers, peer
lists, the run instructions and the "open" items in them are superseded by the
sections above.

Goal: run the new Doichain Core **31.1** (nc31.1 / Bitcoin Core 31 base, with the
DigiShield fast‑DAA hard fork) together with p2pool on a fresh host (e.g. Hetzner),
instead of the legacy 0.20 images this repo shipped.

> **Status 2026‑09‑11, 16:05 UTC — the fork is LIVE.** Block **431017** was mined
> under the new rules and is `status: active`. See *Rollout status* below.

## What this branch changes

- **`doichain/Dockerfile` rewritten for CMake / Core 31.** The old file was
  `FROM ubuntu:18.04` and built with `autogen.sh && configure && make` plus
  BerkeleyDB 4.8 — that is 0.20‑era and cannot build 31.1. The new file is
  `FROM debian:12`, installs `cmake / libevent / libboost / libsqlite3` (no BDB),
  and builds with `cmake … && cmake --build … --target doichaind doichain-cli`.
  Source is pinned by `--build-arg DOICHAIN_VER` (now `v31.1.1`).
- **`docker-compose-mining.yml`**: the `doichain` service now **builds from
  `./doichain`** at `DOICHAIN_VER` and tags the image `doichain/core:v31.1.1`,
  instead of pulling the legacy `doichain/core:dc0.20.1.13`.
- **`bitcoin-init` service** bootstraps the pruned parent chain from the doi.works
  nightly snapshot, replacing the dead `prunednode.today` URL.
- **Image fixes** — see *Bugs found and fixed* below.

## Version

Ship this as a **new version** — never reuse `v31.1.0`, because it is a
consensus / hard‑fork change (a node must not silently look identical to a
pre‑fork one). Tag: **`v31.1.1`** on `doichain-core` (`feat/digishield-daa`), same
string for the image tag here. The version string is only operational; what
enforces the fork is the activation height in `chainparams`
(`DoiDifficultyHeight`), not the version number.

## Rollout status (2026‑09‑11)

**The flag day has been reached.** Original tip was 431016; block **431017** was
mined ~9 h later and validates under the new consensus:

```
hash    75a4ca09bf092862061e0e1c9f066145962f222ef965f3e9ccc27c6bcd0da320
height  431017
bits    1a100334
```

`0x1a100334` is exactly `nDoiDifficultyResetBits` (`0x1a0400cd`, mantissa 262 349)
multiplied by the bounded emergency valve **×4** (mantissa 1 049 396) — the 9‑hour
gap far exceeded `nDoiMinDifficultyGap`. The DAA behaved exactly as designed.

**We mined it ourselves.** The coinbase of 431017 pays 12.5 DOI to
`NFgT2Gv6C9B9WaWQ51bz9FmPinYmy8wqTE` — the payout address handed to our p2pool —
and the block timestamp (14:33:16 UTC) is the same second p2pool logged its first
`Got new merged mining work!`. p2pool showed 0 H/s *local* hashrate: the share came
off the shared p2pool sharechain and met the (valve‑relaxed) Doichain aux target.
That is merge mining working as intended.

**It propagated to the legacy network.** Asked directly via `getblockfrompeer`, the
old `/Satoshi:0.20.99/` node `116.203.99.217` served the block body — confirming in
practice that pre‑fork nodes accept and keep the post‑fork block.

**But so far it is exactly one block.** `getchaintips` shows a single tip at
431017; no block above it exists. Earlier notes in this file claimed a tip of
434542 — that was wrong: it came from peers' self‑declared height in the version
handshake, which two peers assert without ever serving headers to back it up.
Verified chain state is **431017**. Sustained hashrate is still needed before the
chain runs at its normal cadence.

**No fork against the legacy nodes.** Doichain historically never enforced `nBits`
(the chain was launched with the difficulty check disabled for the premine), so the
old `0.20.x` nodes accept this block despite its "wrong" difficulty. The DAA change
is therefore effectively a soft rollout.

Activation heights (`DoiDifficultyHeight = DoiPowCheckHeight = DoiOwnershipHeight =
431017`) are now **in the past and need no further adjustment**.

### Parameters as shipped

- **Reset difficulty for 30 TH/s** = `H · 600 / 2³²` = 4 190 952, i.e.
  `nDoiDifficultyResetBits = 0x1a0400cd`. (10/20/50/100 TH/s →
  `0x1a0c0269 / 0x1a060134 / 0x1a0266e1 / 0x1a013370`.)
- Emergency valve `nDoiMinDifficultyGap = 3600` s, bounded `×4`.
- `nMinimumChainWork` = chainwork of block **400000**
  (`0x…ddad217da2329b6043b3`) — deliberately *not* the tip, see below.
- `defaultAssumeValid` = hash of 431016.

## Bugs found and fixed (2026‑09‑11)

Bringing up p2pool surfaced six independent defects, each of which alone stopped a
fresh node. Verified live on `doichain-core`.

| # | Defect | Fix |
|---|---|---|
| 1 | Headers presync never started: `TryLowWorkHeadersSync` tested *entry count* (2000) for a "full" message, but AuxPoW headers are ~2.3 kB so peers cap at the **4 MiB byte** limit (~1792 headers). Every peer's chain was discarded as low‑work. | `doichain-core@5cddda8` — use the byte‑aware `IsHeadersListMax()`, already used at the other two call sites |
| 2 | Presync then aborted at height 2016: `PermittedDifficultyTransition` applied the legacy 4× clamp, but the first retarget moves the target by **~41×** because the chain launched with the difficulty check disabled. | `doichain-core@a87dde5` — skip the check below `DoiPowCheckHeight`, mirroring `ContextualCheckBlockHeader` |
| 3 | `nMinimumChainWork` pinned to the **exact tip** work: presync ends on a batch boundary short of the tip, never cleared the floor → `insufficient work`, 90 connects / 100 disconnects, endless restart. | `doichain-core@510da7a` — use block 400000's chainwork (~31k blocks slack), as upstream does |
| 4 | Node could not start with listening enabled: P2P (8338) and RPC (8339) are adjacent and Core derives the onion target as **P2P+1 = the RPC port**, pushed into `onion_binds` *unconditionally* (before the `if (listenonion)` check) → `Failed to listen on any port`. `-listenonion=0` does **not** help. | `bind=0.0.0.0:8338` in the generated conf |
| 5 | `daemon=1` in the conf plus `start.sh` ending in `exec /bin/bash`: doichaind forked away, PID 1 was bash. Container liveness depended on an attached TTY, crashes went unnoticed, `docker stop` signalled bash. | drop `daemon=1`, pass `-daemon=0`, `exec` through so doichaind is PID 1 |
| 6 | `doichain-start.sh` ran bare `doichaind` with no `-datadir`, falling back to `$HOME/.doichain` **inside the container** → generated conf ignored and the chain lost on every recreate. | `-datadir=/home/doichain/data/doichain` |

Result, on a fresh node with no stopgap: headers `0 → 431017` in **~80 seconds**,
`Ignoring low-work chain` 0×, `invalid difficulty transition` 0×, `insufficient
work` 0×.

## Next step: clean reinstall rehearsal on the Hetzner node

Only **one** node has been rolled out so far, and it is worth tearing down and
rebuilding from scratch — because **nothing currently runs the way compose would
run it**. Every container on the host was started by hand with an overridden
entrypoint:

```
doichain   entrypoint=["doichaind"]              <- manual
bitcoin    entrypoint=["bitcoind"]               <- manual
p2pool     entrypoint=["/usr/bin/pypy"]          <- manual
```

So the path a new operator actually takes — `docker compose up` — has never been
executed end to end. A clean redo validates exactly that, and is the cheapest way
to find the next surprise before other nodes are migrated.

**Risk to the network: none.** The node runs with `-listen=0` and has
`connections_in: 0` — it is a pure leaf serving nobody. The chain advanced from
431017 to 434542 without it.

### :rotating_light: Back up the datadir first — it may be the only copy

Our node is currently the **only** one running the new consensus
(`DoiDifficultyHeight = 431017`). The other nodes do not have it: the `0.20.99`
peers sit at ~**430990**, i.e. *behind* the fork, and the `31.1.0` nodes predate
the rollout chainparams (commit `8688c86`), so they do not carry the flag day
either. None of them can serve a block past the fork.

**Update — this turned out better than feared.** The freshly synced node first
showed 431017 as `status: headers-only`, which looked like nobody could serve the
post‑fork block. Asked explicitly with `getblockfrompeer`, however, the old
`/Satoshi:0.20.99/` node `116.203.99.217` **did** serve the block body, and the node
went to `status: active`. The post‑fork block is therefore held by the legacy
network too, not only by us — a wiped node can get it back. The `headers-only`
state was a fetch that never got scheduled, not an availability gap.

Back up anyway before deleting anything — it is 1.2 GB and buys a guaranteed
rollback if the rehearsal goes sideways:

```bash
docker run --rm -v doichain-data:/d -v /root:/out alpine:3.20 \
  tar czf /out/doichain-data-backup.tgz -C /d .
# then copy it off the machine
```

Restoring that volume is also the fallback if the rehearsal cannot resync.

### Preconditions (all of these, or the node will not come back)

1. **Peer list is mandatory.** With the DNS seeds dead (see below) a fresh node
   never finds the network. The `-addnode` entries are now in the compose file.
   *This is the one that would strand the host.*
2. **Keep `bitcoin-data` (11.3 GB).** Only ~7.6 GB is free on the host; a fresh
   pruned-parent bootstrap needs ~24 GB peak and cannot succeed here. Wipe only
   the Doichain side (`doichain-data`, test volumes).
3. **The image cannot be built on the host** — compose builds doichaind from the
   *private* `doichain-core`, to which the host has no access. Publish
   `doichain/core:v31.1.2` to Docker Hub, or pre-load it before `compose up`.

### Version

The fixed binary is **not** the `v31.1.1` that was shipped — it carries four
consensus-adjacent commits. By this document's own rule (never reuse a version),
it goes out as **`v31.1.2`**; `CLIENT_VERSION_BUILD` and the compose tag are set
accordingly.

### Sequence

```
# 1. keep bitcoin-data, drop the Doichain side
docker rm -f doichain p2pool doichain-fix3
docker volume rm doichain-data doichain-fix3-vol
# 2. pre-load doichain/core:v31.1.2   (until it is on Docker Hub)
# 3. the real path, for the first time
docker compose -f docker-compose-mining.yml up -d
```

Then verify: doichaind is PID 1, conf and chain land on the volume, the node finds
peers, p2pool reports `Got new merged mining work!`. Only after that migrate the
remaining nodes one at a time.

## Open issues

- [ ] **Peer discovery is broken for fresh nodes.** :rotating_light: `dnsseed.doichain.org`
  and `seed.doi.works` return **0 addresses**, and the binary has **no fixed seeds**
  compiled in (`Added 0 fixed seeds from reachable networks`). A node with an empty
  `addrman` therefore cannot find the network at all. Until the seeds are fixed,
  new operators must be given explicit `-addnode=` / `-connect=` entries. This is
  the most likely thing to block third‑party node operators.
- [ ] **`wallet=1` in the generated conf is wrong** — *confirmed*, not just
  suspected: Core 31 reads it as "load a wallet named `1`" and logs
  `Skipping -wallet path that doesn't exist … '/home/doichain/data/doichain/1'`.
  A mining node paying p2pool to an external address needs no wallet — drop it, or
  load a named wallet explicitly.
- [ ] **Publish `doichain/core:v31.1.1` to Docker Hub.** The compose still builds
  from the **private** `doichain-core`, so `docker compose build` fails on a clean
  host.
- [ ] **Rebuild/republish `doichain/bitcoind`** — the repo source already points at
  doi.works, but the published image still carries the dead `prunednode.today` URL.
  (The source also needed `--strip-components=1`, otherwise the snapshot unpacks to
  `<datadir>/.bitcoin/` and bitcoind still does a full IBD.)
- [ ] **electrumX: add it (new service).** See #2 — and read the premine warning
  there first: any difficulty/retarget validation must be disabled below 431017,
  two DAA eras must be handled, and AuxPoW headers are ~2.3 kB, not 80 bytes.
- [ ] **Testnet has the same port collision** (18338/18339) as defect #4 and needs
  the same explicit `bind=`.
- [ ] `UA_NAME` is still `"Satoshi"` (we advertise `/Satoshi:31.1.1/`). Deliberately
  left for after the flag day, to avoid adding a network‑visible variable mid‑rollout.

## Verified working

- **p2pool ↔ doichaind merge mining** — `Got new merged mining work!`, p2pool joined
  the sharechain and processes shares. p2pool reads bitcoin RPC credentials from
  `bitcoin.conf` via the `~/.bitcoin` symlink; it has **no** `--bitcoind-rpc-username`
  flag. No local miner attached yet, so the stratum path (`:9332`) is still untested.
- **Image builds end to end** (Debian 12 / CMake, ~4.5 min).
- **Pruned parent bootstrap** from `https://www.doi.works/pruned/bitcoin-pruned.tgz`
  (11.0 GB, refreshed nightly ~02:15 UTC).

## Run on Hetzner

```bash
git clone -b feat/doichain-31.1 https://github.com/Doichain/doichain-install.git
cd doichain-install
cp .env.mining.example .env         # set YOUR payout addresses
docker compose -f docker-compose-mining.yml build doichain
docker compose -f docker-compose-mining.yml up -d
# p2pool UI on :9332, doichaind RPC on :8339
```

**Superseded (2026-09-13): do not follow this block.** It builds the image from
source, and the two peers once recommended here (`2.28.75.43`,
`136.243.155.62`) stall one block below the fork. Use the *Run* section at the
top.

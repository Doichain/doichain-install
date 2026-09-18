# Relaunch work log, September 2026

This is the record of the 31.1 relaunch as it happened: what was found, what was
fixed and in which order. **Version numbers, peer lists and run instructions in
here are superseded** by [stack-31.1.md](stack-31.1.md); it is kept because the
reasoning behind several decisions only exists here.

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

## Addendum 2026-09-18: the chain did split after all, one block later

Two statements above were true when they were written and are not any more. They
stay where they are; this is what has happened since.

**"No fork against the legacy nodes."** That held for the flag day block: the old
0.20 nodes accepted 431017 despite its new difficulty, because Doichain never
enforced `nBits`. Both chains then built their next block on it — and there they
parted:

| Height | This chain (v31.1.x) | The 0.20 chain |
|---|---|---|
| 431016 | `4f5e8c0e4efb3504f8923ea175e4e5e688963819dcfbe33cc7f5a28c33616823` | the same block |
| 431017 | `75a4ca09bf092862061e0e1c9f066145962f222ef965f3e9ccc27c6bcd0da320` | the same block |
| **431018** | **`71d50ff12b090561cc918ddb560334b4350758c7eace3f058dd332fb112f4b67`** | **`bab49c132328d09664261c3061608442408d4f667eaa457ed874b879923f2d34`** |

Both blocks at 431018 name `75a4ca09…` as their parent. `getblockhash 431018` is
therefore the one question that tells the chains apart; asking for 431017 proves
nothing, because both have it.

**The tip.** This chain stood at **432,230** on 2026-09-18, the old one at
**444,404** — it is ahead because it kept mining at the old difficulty (~203 M
against ~717 M here). The number *434542* used further up in "Risk to the
network: none" is of that kind: the same file debunks it a few paragraphs
earlier as a peer's self-declared height, and it was never a block of this chain.

What keeps a v31.1.x node here is the difficulty rule from
`DoiPowCheckHeight = 431017` (`validation.cpp`), not a checkpoint — Core 31 has
none — and not `nMinimumChainWork` either: a floor high enough to exclude the old
chain would exclude this one too, which has less work.

Measured against all four `*.doi.works` ElectrumX servers, `doi-explorer.le-space.de`
and the explorer of the old chain.


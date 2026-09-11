# Upgrade to Doichain Core 31.1 (branch `feat/doichain-31.1`)

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

**The chain is mining again.** By 16:15 UTC the network tip was **434 542**, i.e.
**3 525 blocks** past the flag day. That is the expected post‑reset profile: the
reset target is deliberately on the easy side, blocks come fast, and DigiShield
ratchets the difficulty back up block by block until it settles at the real
hashrate. Before the fork the chain had produced *no* block for ~9 hours.

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

Until the DNS seeds are fixed, add known peers to the `doichain` service, e.g.
`-addnode=2.28.75.43 -addnode=136.243.155.62`.

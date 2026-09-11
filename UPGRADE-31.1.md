# Upgrade to Doichain Core 31.1 (branch `feat/doichain-31.1`)

Goal: run the new Doichain Core **31.1** (nc31.1 / Bitcoin Core 31 base, with the
DigiShield fast‑DAA hard fork) together with p2pool on a fresh host (e.g. Hetzner),
instead of the legacy 0.20 images this repo shipped.

## What this branch changes

- **`doichain/Dockerfile` rewritten for CMake / Core 31.** The old file was
  `FROM ubuntu:18.04` and built with `autogen.sh && configure && make` plus
  BerkeleyDB 4.8 — that is 0.20‑era and cannot build 31.1. The new file is
  `FROM debian:12`, installs `cmake / libevent / libboost / libsqlite3` (no BDB),
  and builds with `cmake … && cmake --build … --target doichaind doichain-cli`.
  Source is pinned by `--build-arg DOICHAIN_VER` (default `feat/digishield-daa`;
  set it to the release tag, e.g. `v31.1.1`, once cut).
- **`docker-compose-mining.yml`**: the `doichain` service now **builds from
  `./doichain`** at `DOICHAIN_VER` and tags the image `doichain/core:v31.1.1`,
  instead of pulling the legacy `doichain/core:dc0.20.1.13`.

## Version

Ship this as a **new version** — never reuse `v31.1.0`, because it is a
consensus / hard‑fork change (a node must not silently look identical to a
pre‑fork one). Recommended: **`v31.1.1`** as the tag on `doichain-core`
(`feat/digishield-daa`), and use the same string for the image tag here.
Note: the version string is only operational; what actually enforces the fork is
the activation height baked into `chainparams` (`DoiDifficultyHeight`), not the
version number.

## Rollout parameters (as of 2026‑09‑11)

Confirmed against a freshly synced mainnet node (`getblockchaininfo`:
`blocks=431016, headers=431016, ibd=false`) — matches the public explorer.

- **Activation height must be `tip + 1` (≈ 431017).** The stuck difficulty
  (~28.2 billion) corresponds to ~202 PH/s; with the planned ~30 TH/s a single
  block at the old difficulty would take ~47 days, so the chain cannot grind up
  to any height above `tip+1`. Set `DoiDifficultyHeight = DoiPowCheckHeight =
  tip+1`; the upgrade window is coordinated **off‑chain** (everyone installs
  31.1 first), not by an on‑chain grace period.
- **Reset difficulty for 30 TH/s** = `H · 600 / 2³²` = **4,190,952**, i.e.
  `nDoiDifficultyResetBits = 0x1a0400cd`. (10/20/50/100 TH/s →
  `0x1a0c0269 / 0x1a060134 / 0x1a0266e1 / 0x1a013370`.) Re‑measure the real
  hashrate right before launch and set it slightly on the easy side.
- Emergency valve `nDoiMinDifficultyGap = 3600` s, bounded `×4`.

## Still to do on this branch (not done yet)

- [ ] **Test‑build the image end to end** (`docker compose -f
  docker-compose-mining.yml build doichain`). The Dockerfile follows the proven
  Debian‑12 CMake recipe but the in‑container build has **not** been executed in
  CI yet.
- [ ] **electrumX: add it (new service).** It is only "(planned)" in the README
  today — there is nothing to "upgrade". Needs its own container + config pointed
  at doichaind RPC (8339) + a port; verify against the Core‑31 RPC.
- [ ] **p2pool: verify against 31.1.** The image `doichain/p2pool:v34.0` talks to
  doichaind over RPC (merge mining, `getauxblock`/`getblocktemplate`). These RPCs
  exist in 31.1, so it should work unchanged — confirm on the test‑build.
- [ ] **`entrypoint.sh` conf review for Core 31.** The generated `doichain.conf`
  contains `wallet=1`; in Core 31 `wallet=<name>` names a wallet to load. A
  mining node paying p2pool to an external address needs no wallet — drop
  `wallet=` there, or load a named wallet explicitly. Verify on first boot.
- [ ] Optionally bump `doichain/bitcoind:v0.20.0` (the merge‑mining parent), and
  point the mainnet compose (`docker-compose-email-doi-mainnet.yml`) at the new
  image too.

## Run on Hetzner (once the parameters are final and the image test‑builds)

```bash
git clone -b feat/doichain-31.1 https://github.com/Doichain/doichain-install.git
cd doichain-install
cp .env.mining.example .env         # set the payout addresses
docker compose -f docker-compose-mining.yml build doichain
docker compose -f docker-compose-mining.yml up -d
# p2pool UI on :9332, doichaind RPC on :8339
```

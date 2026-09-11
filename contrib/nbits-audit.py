#!/usr/bin/env python3
"""
nbits-audit — findet Bloecke, deren Difficulty (nBits) nicht der Konsensregel folgt.

Hintergrund
-----------
Doichain hat die nBits-Regel historisch NIE erzwungen (die Kette wurde mit
abgeschalteter Difficulty-Pruefung fuer das Premining gestartet; erst ab
DoiPowCheckHeight wird geprueft). Ein Miner konnte sich seine Schwierigkeit
daher frei aussuchen. Dieses Script rechnet fuer jeden Block nach, welchen
nBits-Wert die Legacy-Regel verlangt haette, und markiert jede Abweichung.

Regel (Bitcoin-Legacy, unterhalb DoiDifficultyHeight):
  * Hoehe % 2016 != 0  ->  nBits MUSS gleich dem Vorgaenger sein
  * Hoehe % 2016 == 0  ->  Retarget: CalculateNextWorkRequired(), gedeckelt auf 4x

Aufruf
------
  python3 nbits-audit.py [--rpc URL] [--user U] [--pass P] [--from N] [--to N]
  python3 nbits-audit.py --csv befunde.csv
"""
import argparse, json, sys, time
import urllib.request

# ---------------------------------------------------------------- Consensus
POW_LIMIT      = int("0000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", 16)
TARGET_TIMESPAN = 14 * 24 * 60 * 60      # 1_209_600 s
TARGET_SPACING  = 10 * 60                # 600 s
INTERVAL        = TARGET_TIMESPAN // TARGET_SPACING   # 2016


def compact_to_target(bits: int) -> int:
    exp, mant = bits >> 24, bits & 0x007FFFFF
    if bits & 0x00800000:                     # negatives Vorzeichen -> ungueltig
        return -1
    return mant >> (8 * (3 - exp)) if exp <= 3 else mant << (8 * (exp - 3))


def target_to_compact(target: int) -> int:
    if target <= 0:
        return 0
    size = (target.bit_length() + 7) // 8
    compact = target << (8 * (3 - size)) if size <= 3 else target >> (8 * (size - 3))
    if compact & 0x00800000:                  # oberstes bit belegt -> ein byte weiter
        compact >>= 8
        size += 1
    return compact | (size << 24)


def difficulty(bits: int) -> float:
    """Wie Bitcoin Cores GetDifficulty(): relativ zu 0x1d00ffff, NICHT zum powLimit.
    Damit stimmen die Werte mit denen von getblockheader und dem Explorer ueberein."""
    shift = (bits >> 24) & 0xFF
    d = float(0x0000FFFF) / float(bits & 0x00FFFFFF)
    while shift < 29:
        d *= 256.0
        shift += 1
    while shift > 29:
        d /= 256.0
        shift -= 1
    return d


def calculate_next_work(last_bits: int, last_time: int, first_time: int) -> int:
    """Nachbildung von CalculateNextWorkRequired() (mainnet, enforce_BIP94=false)."""
    actual = last_time - first_time
    actual = max(actual, TARGET_TIMESPAN // 4)
    actual = min(actual, TARGET_TIMESPAN * 4)
    new = compact_to_target(last_bits) * actual // TARGET_TIMESPAN
    return target_to_compact(min(new, POW_LIMIT))


# ---------------------------------------------------------------- RPC
class RPC:
    def __init__(self, url, user, password):
        self.url, self.user, self.password = url, user, password
        import base64
        self.auth = base64.b64encode(f"{user}:{password}".encode()).decode()

    def batch(self, calls):
        """calls = [(method, [params]), ...] -> [result, ...]"""
        payload = [{"jsonrpc": "1.0", "id": i, "method": m, "params": p}
                   for i, (m, p) in enumerate(calls)]
        req = urllib.request.Request(
            self.url, data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json",
                     "Authorization": "Basic " + self.auth})
        with urllib.request.urlopen(req, timeout=600) as r:
            out = json.load(r)
        out.sort(key=lambda x: x["id"])
        for o in out:
            if o.get("error"):
                raise RuntimeError(o["error"])
        return [o["result"] for o in out]

    def one(self, method, params=None):
        return self.batch([(method, params or [])])[0]


# ---------------------------------------------------------------- Hauptlauf
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rpc",  default="http://127.0.0.1:8339/")
    ap.add_argument("--user", default="admin")
    ap.add_argument("--password", dest="pw", default="verify")
    ap.add_argument("--from", dest="h_from", type=int, default=1)
    ap.add_argument("--to",   dest="h_to",   type=int, default=0, help="0 = bis zur Spitze")
    # ACHTUNG: grosse Stapel koennen den Node in den OOM-Kill treiben. Ein Lauf mit
    # 4000 hat doichaind auf einem 3,8-GB-Host abgeschossen (ExitCode 137). 200 ist
    # schonend und immer noch schnell genug (~1500 Bloecke/s).
    ap.add_argument("--batch", type=int, default=200)
    ap.add_argument("--pause", type=float, default=0.02,
                    help="Pause zwischen den Stapeln in Sekunden (entlastet den Node)")
    ap.add_argument("--csv", default=None)
    a = ap.parse_args()

    rpc = RPC(a.rpc, a.user, a.pw)
    tip = rpc.one("getblockcount")
    h_to = a.h_to or tip
    print(f"Kette bis Hoehe {tip}; untersuche {a.h_from}..{h_to}\n", flush=True)

    # ---- Header einlesen (gebatcht: hash-liste, dann header-liste) --------
    lo = max(0, a.h_from - INTERVAL - 1)        # Vorlauf fuer Retarget-Bezug
    heights = list(range(lo, h_to + 1))
    hdr = {}
    t0 = time.time()
    for i in range(0, len(heights), a.batch):
        chunk = heights[i:i + a.batch]
        hashes = rpc.batch([("getblockhash", [h]) for h in chunk])
        headers = rpc.batch([("getblockheader", [hh]) for hh in hashes])
        for h, head in zip(chunk, headers):
            hdr[h] = (int(head["bits"], 16), head["time"])
        done = i + len(chunk)
        pct = 100.0 * done / len(heights)
        print(f"\r  eingelesen {done}/{len(heights)} ({pct:.1f}%) "
              f"{done/max(time.time()-t0,0.01):.0f} Bloecke/s", end="", flush=True)
        if a.pause:
            time.sleep(a.pause)
    print(f"\n  fertig in {time.time()-t0:.0f}s\n", flush=True)

    # ---- Auswertung ------------------------------------------------------
    befunde = []
    for h in range(max(a.h_from, lo + INTERVAL + 1), h_to + 1):
        if h not in hdr or (h - 1) not in hdr:
            continue
        bits_ist, t_ist = hdr[h]
        bits_prev, t_prev = hdr[h - 1]

        if h % INTERVAL != 0:
            bits_soll = bits_prev
            art = "kein Retarget — nBits musste unveraendert bleiben"
        else:
            # Doichain/Namecoin weicht hier von Bitcoin ab (pow.cpp):
            #   nBlocksBack = Interval - 1                     (Bitcoin, 2015)
            #   nBlocksBack = Interval  ab nAuxpowStartHeight  (Namecoin, 2016)
            # Mainnet hat nAuxpowStartHeight = 1, also gilt die Namecoin-Variante
            # fuer alle Retargets ausser dem allerersten bei Hoehe 2016.
            n_back = INTERVAL if h > INTERVAL else INTERVAL - 1
            first = hdr.get((h - 1) - n_back)
            if first is None:
                continue
            bits_soll = calculate_next_work(bits_prev, t_prev, first[1])
            art = "Retarget — berechneter Wert"

        if bits_ist != bits_soll:
            d_ist, d_soll = difficulty(bits_ist), difficulty(bits_soll)
            befunde.append({
                "hoehe": h, "zeit": t_ist,
                "bits_ist": f"{bits_ist:08x}", "bits_soll": f"{bits_soll:08x}",
                "diff_ist": d_ist, "diff_soll": d_soll,
                "faktor": (d_soll / d_ist) if d_ist else float("inf"),
                "art": art,
            })

    # ---- Bericht ---------------------------------------------------------
    geprueft = h_to - max(a.h_from, lo + INTERVAL + 1) + 1
    print("=" * 78)
    print(f"GEPRUEFT : {geprueft:,} Bloecke")
    print(f"BEFUNDE  : {len(befunde):,} Bloecke mit abweichender Difficulty")
    if not befunde:
        print("\n  Keine Abweichung — die nBits folgen ueberall der Regel.")
        return
    leichter = [b for b in befunde if b["faktor"] > 1]
    haerter  = [b for b in befunde if b["faktor"] <= 1]
    print(f"  davon LEICHTER als erlaubt (Ausnutzung): {len(leichter):,}")
    print(f"  davon haerter  als erlaubt (harmlos)  : {len(haerter):,}")

    # zusammenhaengende Serien = eine Angriffsphase
    serien, cur = [], []
    for b in befunde:
        if cur and b["hoehe"] == cur[-1]["hoehe"] + 1:
            cur.append(b)
        else:
            if cur: serien.append(cur)
            cur = [b]
    if cur: serien.append(cur)
    print(f"  zusammenhaengende Serien: {len(serien)}")

    print("\n" + "=" * 78)
    print("SERIEN (jeweils Beginn, Laenge, staerkste Erleichterung)")
    print(f"{'von':>9} {'bis':>9} {'laenge':>7} {'max. leichter':>15}  {'beginn (UTC)':>20}")
    print("-" * 78)
    for s in sorted(serien, key=lambda x: -len(x))[:40]:
        mx = max(s, key=lambda b: b["faktor"])
        ts = time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(s[0]["zeit"]))
        print(f"{s[0]['hoehe']:>9} {s[-1]['hoehe']:>9} {len(s):>7} "
              f"{mx['faktor']:>14,.1f}x  {ts:>20}")

    print("\n" + "=" * 78)
    print("EINZELNE BLOECKE mit der groessten Erleichterung")
    print(f"{'hoehe':>9} {'bits ist':>10} {'bits soll':>10} {'diff ist':>16} {'diff soll':>16} {'leichter':>12}")
    print("-" * 78)
    for b in sorted(befunde, key=lambda x: -x["faktor"])[:25]:
        print(f"{b['hoehe']:>9} {b['bits_ist']:>10} {b['bits_soll']:>10} "
              f"{b['diff_ist']:>16,.0f} {b['diff_soll']:>16,.0f} {b['faktor']:>11,.1f}x")

    if a.csv:
        import csv as _csv
        with open(a.csv, "w", newline="") as f:
            w = _csv.DictWriter(f, fieldnames=list(befunde[0].keys()))
            w.writeheader(); w.writerows(befunde)
        print(f"\nCSV geschrieben: {a.csv} ({len(befunde)} Zeilen)")


if __name__ == "__main__":
    sys.exit(main())

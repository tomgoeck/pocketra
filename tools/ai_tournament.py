#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import itertools
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT_DEFAULT = "/Applications/Godot.app/Contents/MacOS/Godot"
STRATEGIES = ["normal", "rush", "turtle", "air", "naval"]


ROW = re.compile(r"^TURNIER\s+(.*)$")


def run_match(godot: str, karte: str, strategien: list[str], seed: int, ticks: int,
              staerke: str, credits: int, verbose: bool) -> list[dict]:

    args = [
        godot, "--headless", "--path", str(ROOT / "game"),


        "--quit-after", str(max(120000, ticks * 80)),
        "--",
        "--autostart", "--map", karte,
        "--ai", str(len(strategien)),
        "--seed", str(seed),
        "--starting-units", "none",
        "--credits", str(credits),
        "--test-ai", "--test-ai-until", str(ticks),
        "--ai-difficulty", staerke,
        "--ai-strategies", ",".join(strategien),


        "--game-speed", "4",
    ]
    proc = subprocess.run(args, capture_output=True, text=True, timeout=60 * 30)
    out = proc.stdout + proc.stderr
    if verbose:
        sys.stderr.write(out)
    rows = []
    for line in out.splitlines():
        m = ROW.match(line.strip())
        if not m:
            continue
        d = {}
        for part in m.group(1).split():
            if "=" in part:
                k, v = part.split("=", 1)
                d[k] = v
        d["seed"] = str(seed)
        d["karte"] = karte
        rows.append(d)
    if not rows:
        sys.stderr.write(f"WARNUNG: kein TURNIER-Ergebnis für {strategien} Seed {seed}\n")
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot", default=GODOT_DEFAULT)
    ap.add_argument("--karte", default="a-path-beyond")
    ap.add_argument("--paare", nargs="*", default=[], metavar="A:B",
                    help="Paarungen, z. B. rush:turtle (auch drei: rush:turtle:air)")
    ap.add_argument("--alle", action="store_true", help="jede Spielweise gegen jede andere")
    ap.add_argument("--seeds", nargs="*", type=int, default=[1])
    ap.add_argument("--ticks", type=int, default=9000)
    ap.add_argument("--staerke", default="normal", choices=["easy", "normal", "hard"])
    ap.add_argument("--credits", type=int, default=5000)
    ap.add_argument("--csv", default="", help="Ergebnisse zusätzlich als CSV ablegen")
    ap.add_argument("--laut", action="store_true", help="Godot-Ausgabe durchreichen")
    a = ap.parse_args()

    paarungen: list[list[str]] = [p.split(":") for p in a.paare]
    if a.alle or not paarungen:
        paarungen = [list(p) for p in itertools.combinations(STRATEGIES, 2)]
    for p in paarungen:
        for s in p:
            if s not in STRATEGIES:
                ap.error(f"unbekannte Spielweise: {s}")

    alle: list[dict] = []
    for paar in paarungen:
        for seed in a.seeds:
            print(f"… {' gegen '.join(paar)} (Seed {seed}, {a.ticks} Ticks)", flush=True)
            alle += run_match(a.godot, a.karte, paar, seed, a.ticks, a.staerke, a.credits, a.laut)

    if not alle:
        print("Keine Ergebnisse.")
        return 1


    spalten = ["gebaut", "superwaffen", "trupps", "erster_angriff", "lebend", "ertrag"]
    zusammen: dict[str, dict] = {}
    for r in alle:
        z = zusammen.setdefault(r.get("strategie", "?"), {"laeufe": 0, **{c: 0 for c in spalten}})
        z["laeufe"] += 1
        for c in spalten:
            z[c] += int(r.get(c, 0) or 0)

    kopf = f"{'Spielweise':<12}{'Läufe':>6}{'Einheiten':>11}{'Superw.':>9}{'Trupps':>8}{'1. Angriff':>12}{'lebend':>8}{'Ertrag':>10}"
    print()
    print(kopf)
    print("-" * len(kopf))
    for name in sorted(zusammen, key=lambda k: -zusammen[k]["lebend"] / max(1, zusammen[k]["laeufe"])):
        z = zusammen[name]
        n = max(1, z["laeufe"])
        print(f"{name:<12}{z['laeufe']:>6}{z['gebaut'] // n:>11}{z['superwaffen'] // n:>9}"
              f"{z['trupps'] // n:>8}{z['erster_angriff'] // n:>12}{z['lebend'] // n:>8}{z['ertrag'] // n:>10}")

    if a.csv:
        out = Path(a.csv)
        out.parent.mkdir(parents=True, exist_ok=True)
        felder = sorted({k for r in alle for k in r})
        with out.open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=felder)
            w.writeheader()
            w.writerows(alle)
        print(f"\n{len(alle)} Zeilen → {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

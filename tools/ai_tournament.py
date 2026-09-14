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


SPALTEN = [
    "gebaut", "superwaffen", "trupps", "erster_angriff", "lebend", "ertrag",
    "armee", "bargeld", "belagerer_verloren", "in_turmreichweite", "tuerme", "trupp_verluste",
    "schwere_verluste",
]


TITEL = {
    "gebaut": ("Einheiten", 11), "superwaffen": ("Superw.", 9), "trupps": ("Trupps", 8),
    "erster_angriff": ("1. Angriff", 12), "lebend": ("lebend", 8), "ertrag": ("Ertrag", 9),
    "armee": ("Armee", 9), "bargeld": ("Bargeld", 9),
    "belagerer_verloren": ("Belag.verl.", 12), "in_turmreichweite": ("i.Turmrw.", 11),
    "tuerme": ("Türme", 7), "trupp_verluste": ("Tr.verl.", 10),
    "schwere_verluste": ("schw.Verl.", 11),
}


def zahl(r: dict, spalte: str) -> int:

    try:
        return int(r.get(spalte, 0) or 0)
    except ValueError:
        return 0


def mittel(rows: list[dict]) -> dict[str, dict]:

    zusammen: dict[str, dict] = {}
    for r in rows:
        z = zusammen.setdefault(r.get("strategie", "?"), {"laeufe": 0, **{c: 0 for c in SPALTEN}})
        z["laeufe"] += 1
        for c in SPALTEN:
            z[c] += zahl(r, c)
    for z in zusammen.values():
        n = max(1, z["laeufe"])
        for c in SPALTEN:
            z[c] //= n
    return zusammen


def bestenliste(rows: list[dict]) -> dict[str, dict]:

    zusammen = mittel(rows)
    kopf = f"{'Spielweise':<12}{'Läufe':>6}" + "".join(f"{TITEL[c][0]:>{TITEL[c][1]}}" for c in SPALTEN)
    print()
    print(kopf)
    print("-" * len(kopf))
    for name in sorted(zusammen, key=lambda k: -zusammen[k]["lebend"]):
        z = zusammen[name]
        print(f"{name:<12}{z['laeufe']:>6}" + "".join(f"{z[c]:>{TITEL[c][1]}}" for c in SPALTEN))

    for name in sorted(zusammen):
        z = zusammen[name]
        if z["belagerer_verloren"] > 0:
            anteil = 100 * z["in_turmreichweite"] // z["belagerer_verloren"]
            print(f"  {name}: {anteil} % der verlorenen Belagerer starben in Turmreichweite "
                  f"(Ziel < 20 %, docs/KI-STRATEGIE.md §5)")
    return zusammen


def lies_csv(pfad: Path) -> list[dict]:
    with pfad.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def vergleich(alt: Path, neu: Path) -> int:

    for p in (alt, neu):
        if not p.exists():
            sys.stderr.write(f"FEHLER: {p} gibt es nicht\n")
            return 1
    a_rows, n_rows = lies_csv(alt), lies_csv(neu)
    if not a_rows or not n_rows:
        sys.stderr.write("FEHLER: eine der beiden Dateien ist leer\n")
        return 1
    a_mit, n_mit = mittel(a_rows), mittel(n_rows)
    a_mit["ALLE"] = mittel([{**r, "strategie": "ALLE"} for r in a_rows])["ALLE"]
    n_mit["ALLE"] = mittel([{**r, "strategie": "ALLE"} for r in n_rows])["ALLE"]
    print(f"alt: {alt} ({len(a_rows)} Zeilen)    neu: {neu} ({len(n_rows)} Zeilen)")
    for name in sorted(set(a_mit) | set(n_mit), key=lambda k: (k == "ALLE", k)):
        a = a_mit.get(name)
        n = n_mit.get(name)
        if a is None or n is None:
            print(f"\n{name}: nur in {'neu' if a is None else 'alt'} — übersprungen")
            continue
        print(f"\n{name}  (Läufe alt {a['laeufe']}, neu {n['laeufe']})")
        print(f"  {'Kennzahl':<20}{'alt':>10}{'neu':>10}{'Differenz':>12}")
        for c in SPALTEN:
            d = n[c] - a[c]
            print(f"  {c:<20}{a[c]:>10}{n[c]:>10}{d:>+12}")
    return 0


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
    ap.add_argument("--vergleich", nargs=2, metavar=("ALT.CSV", "NEU.CSV"), default=None,
                    help="zwei fertige CSV-Dateien vergleichen (Mittel je Kennzahl und Differenz), "
                         "ohne einen neuen Lauf zu starten")
    a = ap.parse_args()

    if a.vergleich:
        return vergleich(Path(a.vergleich[0]), Path(a.vergleich[1]))

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


    bestenliste(alle)

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

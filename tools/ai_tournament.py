#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import itertools
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT_DEFAULT = "/Applications/Godot.app/Contents/MacOS/Godot"
STRATEGIES = ["normal", "rush", "turtle", "air", "naval"]


ROW = re.compile(r"^TURNIER\s+(.*)$")


KOMMANDEUR = re.compile(r"^KOMMANDEUR(_ENDE|-SPIELER)?\s+(\{.*\})\s*$")


SPALTEN = [
    "gebaut", "superwaffen", "trupps", "erster_angriff", "lebend", "ertrag",
    "armee", "bargeld", "belagerer_verloren", "in_turmreichweite", "tuerme", "trupp_verluste",
    "schwere_verluste",

    "trupp_gather_ticks", "trupp_marsch_ticks", "trupp_kontakte", "trupp_bis_schuss",
    "trupp_ohne_schuss", "sammel_neu", "nachzuegler_stops",


    "flaktuerme", "turm_streuung", "ungedeckt",

    "luftangriffe", "flieger_verloren", "schiffe_verloren", "schiffe_versenkt",


    "gebaut_fahrzeuge", "gebaut_infanterie", "gebaut_luft", "gebaut_schiffe",
    "armee_land", "armee_marine",


    "t_raffinerie", "t_kaserne", "t_fabrik", "t_radar",


    "insel", "bauhoefe", "see_luft_gebaeude",


    "t_gefunden", "aufklaerung",


    "landungen", "t_landung", "gelandet", "boote_verloren", "landung_kontakt",


    "armee_m4", "armee_m8", "armee_m12", "sammler_m4", "sammler_m8", "ertrag_m8", "wellen_m12",
    "t_raffinerie2", "kasse_mittel", "gebaeudeschaden", "gebaeude_zerstoert", "sieg",


    "erobert", "pioniere_verbraucht",
]


TITEL = {
    "gebaut": ("Einheiten", 11), "superwaffen": ("Superw.", 9), "trupps": ("Trupps", 8),
    "erster_angriff": ("1. Angriff", 12), "lebend": ("lebend", 8), "ertrag": ("Ertrag", 9),
    "armee": ("Armee", 9), "bargeld": ("Bargeld", 9),
    "belagerer_verloren": ("Belag.verl.", 12), "in_turmreichweite": ("i.Turmrw.", 11),
    "tuerme": ("Türme", 7), "trupp_verluste": ("Tr.verl.", 10),
    "schwere_verluste": ("schw.Verl.", 11),
    "trupp_gather_ticks": ("Sammeln", 9), "trupp_marsch_ticks": ("Marsch", 8),
    "trupp_kontakte": ("Kontakte", 10), "trupp_bis_schuss": ("bis Schuss", 12),
    "trupp_ohne_schuss": ("o.Schuss", 10), "sammel_neu": ("Sammel neu", 12),
    "nachzuegler_stops": ("Nachz.Stop", 12),
    "flaktuerme": ("Flak", 6), "turm_streuung": ("Streuung", 10), "ungedeckt": ("ungedeckt", 11),
    "luftangriffe": ("Luftang.", 10), "flieger_verloren": ("Flieg.verl.", 12),
    "schiffe_verloren": ("Schiff.verl.", 13), "schiffe_versenkt": ("versenkt", 10),
    "gebaut_fahrzeuge": ("Fahrz.", 8), "gebaut_infanterie": ("Inf.", 7),
    "gebaut_luft": ("Luft", 7), "gebaut_schiffe": ("Schiffe", 9),
    "armee_land": ("Heer", 8), "armee_marine": ("Flotte", 9),
    "t_raffinerie": ("1.Raff.", 9), "t_kaserne": ("1.Kaserne", 11),
    "t_fabrik": ("1.Fabrik", 10), "t_radar": ("1.Radar", 9),
    "insel": ("Insel", 7), "bauhoefe": ("Bauhöfe", 9), "see_luft_gebaeude": ("See/Luft-Geb.", 15),
    "t_gefunden": ("gefunden", 10), "aufklaerung": ("Aufkl.", 8),
    "landungen": ("Landungen", 11), "t_landung": ("1. Landung", 12), "gelandet": ("gelandet", 10),
    "boote_verloren": ("Boote weg", 11), "landung_kontakt": ("Landkontakt", 13),
    "armee_m4": ("Armee M4", 10), "armee_m8": ("Armee M8", 10), "armee_m12": ("Armee M12", 11),
    "sammler_m4": ("Samml.M4", 10), "sammler_m8": ("Samml.M8", 10), "ertrag_m8": ("Ertrag M8", 11),
    "wellen_m12": ("Wellen M12", 12), "t_raffinerie2": ("2.Raff.", 9), "kasse_mittel": ("Kasse", 7),
    "gebaeudeschaden": ("Geb.schaden", 13), "gebaeude_zerstoert": ("Geb.zerst.", 12),
    "sieg": ("Ausgang", 9),
    "erobert": ("erobert", 9), "pioniere_verbraucht": ("Pion.weg", 10),
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


def schreibe_kommandeur(out: str, log_dir: Path, karte: str, strategien: list[str], seed: int,
                        staerke: str) -> int:

    zeilen: list[str] = []
    ende = None
    for line in out.splitlines():
        m = KOMMANDEUR.match(line.strip())
        if not m:
            continue
        try:
            rec = json.loads(m.group(2))
        except json.JSONDecodeError:
            continue
        if m.group(1) == "_ENDE":
            ende = rec
        else:
            zeilen.append(json.dumps(rec, ensure_ascii=False, sort_keys=True))
    if not zeilen and ende is None:
        return 0
    log_dir.mkdir(parents=True, exist_ok=True)
    name = f"{karte}_{'-'.join(strategien)}_{staerke}_s{seed}.jsonl"
    with (log_dir / name).open("w", encoding="utf-8") as f:
        for z in zeilen:
            f.write(z + "\n")
        kopf = {"event": "end", "map": karte, "strategies": strategien, "seed": seed, "level": staerke}
        f.write(json.dumps({**kopf, **(ende or {})}, ensure_ascii=False, sort_keys=True) + "\n")
    return len(zeilen)


def run_match(godot: str, karte: str, strategien: list[str], seed: int, ticks: int,
              staerke: str, credits: int, verbose: bool, log_dir: Path | None = None,
              einheiten: str = "", turbo: int = 0, sparring: bool = False,
              roh: Path | None = None, param: str = "") -> list[dict]:

    args = [
        godot, "--headless", "--path", str(ROOT / "game"),


        "--quit-after", str(max(120000, ticks * 80)),
        "--",

        "--no-update-pack",
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
    if einheiten:

        args += ["--ai-unit-share", einheiten]
    if turbo > 0:
        args += ["--turbo", str(turbo)]
    if sparring:
        args += ["--sparring"]
    if param:

        args += ["--ai-param", param]
    proc = subprocess.run(args, capture_output=True, text=True, timeout=60 * 30)
    out = proc.stdout + proc.stderr
    if roh is not None:
        roh.parent.mkdir(parents=True, exist_ok=True)
        roh.write_text(out, encoding="utf-8")
    if verbose:
        sys.stderr.write(out)
    if log_dir is not None:
        schreibe_kommandeur(out, log_dir, karte, strategien, seed, staerke)
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
    ap.add_argument("--einheiten", default="", metavar="TYP=ANTEIL,...",
                    help="Einheitenanteile aller KIs überschreiben, z. B. arty=300,v2rl=300 "
                         "(Belagerungsgegner erzwingen, docs/KI-LAYA.md §6.8)")
    ap.add_argument("--turbo", type=int, default=0, metavar="N",
                    help="je Bild N Sim-Ticks rechnen (gleiches Ergebnis, viel schneller; 25 ist ein guter Wert)")
    ap.add_argument("--sparring", action="store_true",
                    help="Sparringspartner auf Platz 0 (docs/KI-STRATEGIE.md §21); der Prüfstand "
                         "dazu ist tools/ai_bench.py")
    ap.add_argument("--param", default="", metavar="NAME=WERT,...",
                    help="Stellschrauben aller KI-Plätze überschreiben, z. B. eco_first=0")
    ap.add_argument("--csv", default="", help="Ergebnisse zusätzlich als CSV ablegen")
    ap.add_argument("--laut", action="store_true", help="Godot-Ausgabe durchreichen")
    ap.add_argument("--ki-log", default=str(ROOT / "build" / "ai_log"),
                    help="Ordner für die Kommandeur-Protokolle (.jsonl je Partie); leer = keine")
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
            alle += run_match(a.godot, a.karte, paar, seed, a.ticks, a.staerke, a.credits, a.laut,
                              Path(a.ki_log) if a.ki_log else None, a.einheiten, a.turbo, a.sparring,
                              None, a.param)

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

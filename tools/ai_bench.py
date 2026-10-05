#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ai_tournament as turnier

ROOT = Path(__file__).resolve().parent.parent
KARTEN = ["a-path-beyond", "keep-off-the-grass-2", "forgotten-plains", "green-belt"]
CREDITS = [2500, 5000]
SEEDS = [1, 2, 3, 4]
STILE = ["normal", "rush"]


KENNZAHLEN = [
    ("armee_m4", "Armee M4", "wert"), ("armee_m8", "Armee M8", "wert"), ("armee_m12", "Armee M12", "wert"),
    ("t_fabrik", "1.Fabrik", "tick"), ("t_raffinerie2", "2.Raff.", "tick"),
    ("sammler_m4", "Samml.M4", "wert"), ("sammler_m8", "Samml.M8", "wert"),
    ("ertrag_m8", "Ertrag M8", "wert"), ("kasse_mittel", "Kasse", "wert"),
    ("erster_angriff", "1.Angriff", "tick"), ("wellen_m12", "Wellen M12", "wert"),
    ("gebaeudeschaden", "Geb.schaden", "wert"), ("gebaeude_zerstoert", "Geb.zerst.", "wert"),

    ("erobert", "erobert", "wert"), ("pioniere_verbraucht", "Pion.weg", "wert"),
]


def zahl(r: dict, spalte: str) -> int:
    try:
        return int(r.get(spalte, -1) or -1)
    except ValueError:
        return -1


def mittel(rows: list[dict], spalte: str, art: str) -> tuple[str, int]:

    werte = []
    nie = 0
    for r in rows:
        v = zahl(r, spalte) if spalte in r else -1
        if spalte in r and str(r[spalte]).lstrip("-").isdigit():
            v = int(r[spalte])
        if v < 0 or (art == "tick" and v == 0):
            nie += 1
            continue
        werte.append(v)
    if not werte:
        return "-", nie
    m = sum(werte) / len(werte)
    return (f"{m:.1f}" if m < 20 else f"{m:.0f}"), nie


def ausgang(rows: list[dict]) -> tuple[int, int, int]:

    s = sum(1 for r in rows if zahl(r, "sieg") == 1)
    n = sum(1 for r in rows if zahl(r, "sieg") == 2)
    return s, n, len(rows) - s - n


def schluessel(r: dict) -> tuple:

    return (r.get("karte"), r.get("startgeld"), r.get("seed"), r.get("gegner_stil"))


def punkte(r: dict) -> int:

    return max(0, zahl(r, "armee")) + 500 * max(0, zahl(r, "gebaeude_zerstoert"))


def punktwertung(rs: list[dict], gegner: dict[tuple, dict]) -> tuple[int, int, int]:

    vorn = gleich = hinten = 0
    for r in rs:
        if zahl(r, "sieg") in (1, 2):
            continue
        g = gegner.get((schluessel(r), r.get("strategie") != "sparring"))
        if g is None:
            continue
        a, b = punkte(r), punkte(g)
        if a * 10 > b * 12:
            vorn += 1
        elif b * 10 > a * 12:
            hinten += 1
        else:
            gleich += 1
    return vorn, gleich, hinten


def tabelle(rows: list[dict], gruppen: list[tuple[str, list[dict]]]) -> str:

    gegner: dict[tuple, dict] = {}
    for r in rows:
        gegner[(schluessel(r), r.get("strategie") == "sparring")] = r
    kopf = (f"{'Gruppe':<34}{'Läufe':>6}{'Sieg':>6}{'Ndl.':>6}{'offen':>6}{'vorn':>6}{'gleich':>7}{'hinten':>7}"
            + "".join(f"{t:>12}" for _, t, _ in KENNZAHLEN) + f"{'nie WF':>8}{'nie Angr.':>10}")
    zeilen = [kopf, "-" * len(kopf)]
    for name, rs in gruppen:
        if not rs:
            continue
        s, n, o = ausgang(rs)
        v, g, h = punktwertung(rs, gegner)
        z = f"{name:<34}{len(rs):>6}{s:>6}{n:>6}{o:>6}{v:>6}{g:>7}{h:>7}"
        nie_wf = nie_an = 0
        for spalte, _, art in KENNZAHLEN:
            m, nie = mittel(rs, spalte, art)
            z += f"{m:>12}"
            if spalte == "t_fabrik":
                nie_wf = nie
            if spalte == "erster_angriff":
                nie_an = nie
        z += f"{nie_wf:>8}{nie_an:>10}"
        zeilen.append(z)
    return "\n".join(zeilen)


def gruppen_von(rows: list[dict]) -> list[tuple[str, list[dict]]]:
    ki = [r for r in rows if r.get("strategie") != "sparring"]
    sp = [r for r in rows if r.get("strategie") == "sparring"]
    stile = sorted({r.get("strategie", "?") for r in ki})
    karten = sorted({r.get("karte", "?") for r in rows})
    credits = sorted({r.get("startgeld", "?") for r in rows}, key=lambda c: int(c) if str(c).isdigit() else 0)
    g: list[tuple[str, list[dict]]] = []
    for st in stile:
        g.append((f"KI {st} (alle)", [r for r in ki if r.get("strategie") == st]))
        for c in credits:
            g.append((f"KI {st} Credits {c}", [r for r in ki if r.get("strategie") == st and r.get("startgeld") == c]))
        for k in karten:
            g.append((f"KI {st} {k}", [r for r in ki if r.get("strategie") == st and r.get("karte") == k]))
    g.append(("Sparring (alle)", sp))
    for c in credits:
        g.append((f"Sparring Credits {c}", [r for r in sp if r.get("startgeld") == c]))
    for k in karten:
        g.append((f"Sparring {k}", [r for r in sp if r.get("karte") == k]))
    return g


def vergleich(alt: Path, neu: Path) -> int:
    a = turnier.lies_csv(alt)
    n = turnier.lies_csv(neu)
    if not a or not n:
        sys.stderr.write("FEHLER: eine der beiden Dateien fehlt oder ist leer\n")
        return 1
    print(f"alt: {alt} ({len(a)} Zeilen)    neu: {neu} ({len(n)} Zeilen)")
    for st in sorted({r.get("strategie", "?") for r in a + n}):
        ra = [r for r in a if r.get("strategie") == st]
        rn = [r for r in n if r.get("strategie") == st]
        if not ra or not rn:
            continue
        sa, na, oa = ausgang(ra)
        sn, nn, on = ausgang(rn)
        print(f"\n{st}  (Läufe alt {len(ra)}, neu {len(rn)})")
        print(f"  {'Kennzahl':<16}{'alt':>10}{'neu':>10}{'Faktor':>9}")
        print(f"  {'Siege':<16}{sa:>10}{sn:>10}")
        print(f"  {'Niederlagen':<16}{na:>10}{nn:>10}")
        print(f"  {'offen':<16}{oa:>10}{on:>10}")
        for spalte, titel, art in KENNZAHLEN:
            ma, _ = mittel(ra, spalte, art)
            mn, _ = mittel(rn, spalte, art)
            faktor = "-"
            try:
                if float(ma) > 0:
                    faktor = f"{float(mn) / float(ma):.2f}"
            except ValueError:
                pass
            print(f"  {titel:<16}{ma:>10}{mn:>10}{faktor:>9}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot", default=turnier.GODOT_DEFAULT)
    ap.add_argument("--name", default="pruefstand", help="Name des Laufs: build/mess/<name>.csv und .txt")
    ap.add_argument("--karten", nargs="*", default=KARTEN)
    ap.add_argument("--credits", nargs="*", type=int, default=CREDITS)
    ap.add_argument("--seeds", nargs="*", type=int, default=SEEDS)
    ap.add_argument("--stile", nargs="*", default=STILE, choices=turnier.STRATEGIES)
    ap.add_argument("--staerke", default="hard", choices=["easy", "normal", "hard"])
    ap.add_argument("--ticks", type=int, default=18000)
    ap.add_argument("--turbo", type=int, default=25, help="Sim-Ticks je Bild (0 = Echtzeit)")
    ap.add_argument("--jobs", type=int, default=5, help="gleichzeitige Godot-Prozesse (höchstens 6)")
    ap.add_argument("--ohne-sparring", action="store_true",
                    help="Platz 0 bleibt untätig (die alte Messung, zum Gegenprüfen)")
    ap.add_argument("--param", default="", metavar="NAME=WERT,...",
                    help="Stellschrauben der KI überschreiben, um eine Ursache getrennt zu messen "
                         "(z. B. opening_depot=1,eco_first=0)")
    ap.add_argument("--roh", action="store_true", help="Godot-Ausgabe je Lauf nach build/mess/<name>/ legen")
    ap.add_argument("--vergleich", nargs=2, metavar=("ALT.CSV", "NEU.CSV"), default=None)
    ap.add_argument("--tabelle", default="", metavar="CSV",
                    help="die Tabelle aus einer fertigen CSV neu drucken, ohne einen Lauf zu starten")
    a = ap.parse_args()

    if a.vergleich:
        return vergleich(Path(a.vergleich[0]), Path(a.vergleich[1]))
    if a.tabelle:
        rows = turnier.lies_csv(Path(a.tabelle))
        print(tabelle(rows, gruppen_von(rows)))
        return 0

    out_dir = ROOT / "build" / "mess"
    out_dir.mkdir(parents=True, exist_ok=True)
    laeufe = [(k, c, s, st) for k in a.karten for c in a.credits for s in a.seeds for st in a.stile]

    def lauf(job: tuple[str, int, int, str]) -> list[dict]:
        karte, credits, seed, stil = job
        roh = out_dir / a.name / f"{karte}_{credits}_{stil}_s{seed}.log" if a.roh else None
        rows = turnier.run_match(a.godot, karte, [stil], seed, a.ticks, a.staerke, credits, False,
                                 None, "", a.turbo, not a.ohne_sparring, roh, a.param)
        for r in rows:
            r["startgeld"] = str(credits)
            r["gegner_stil"] = stil
        print(f"  fertig: {karte} Credits {credits} Seed {seed} {stil}", flush=True)
        return rows

    print(f"Prüfstand „{a.name}“: {len(laeufe)} Partien, Stufe {a.staerke}, {a.ticks} Ticks, "
          f"{min(6, max(1, a.jobs))} gleichzeitig", flush=True)
    alle: list[dict] = []
    with ThreadPoolExecutor(max_workers=min(6, max(1, a.jobs))) as pool:
        for rows in pool.map(lauf, laeufe):
            alle += rows
    if not alle:
        print("Keine Ergebnisse.")
        return 1

    text = tabelle(alle, gruppen_von(alle))
    print()
    print(text)
    (out_dir / f"{a.name}.txt").write_text(text + "\n", encoding="utf-8")
    felder = sorted({k for r in alle for k in r})
    with (out_dir / f"{a.name}.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=felder)
        w.writeheader()
        w.writerows(alle)
    print(f"\n{len(alle)} Zeilen → {out_dir / (a.name + '.csv')}, Tabelle → {out_dir / (a.name + '.txt')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEVELS = ["none", "low", "medium", "high", "strong"]


MERKMALE = {
    "credits": ("credits", ("credits",), "cmd_credits_lv"),
    "refineries": ("refineries", ("refineries",), "cmd_refinery_lv"),
    "income": ("income", ("income",), "cmd_trend_percent (Trend)"),
    "army_land": ("army_land", ("army", "land"), "cmd_army_lv"),
    "army_air": ("army_air", ("army", "air"), "cmd_army_lv"),
    "army_naval": ("army_naval", ("army", "naval"), "cmd_army_lv"),
    "enemy_land": ("enemy_land", ("enemy", "land"), "cmd_army_lv"),
    "enemy_air": ("enemy_air", ("enemy", "air"), "cmd_army_lv"),
    "enemy_naval": ("enemy_naval", ("enemy", "naval"), "cmd_army_lv"),
    "enemy_anti_air": ("enemy_anti_air", ("enemy", "anti_air"), "cmd_aa_lv"),
    "air_losses": ("air_losses", ("air_losses_60s",), "cmd_loss_lv"),
    "land_losses": ("land_losses", ("land_losses_60s",), "cmd_loss_lv"),
    "kills": ("kills", ("kills_60s",), "cmd_kill_lv"),
    "base_damage": ("base_damage", ("base_damage_60s",), "cmd_damage_lv"),

    **{f"class_{c}": (f"class_{c}", ("enemy_class", c), "cmd_class_lv")
       for c in ("siege", "armor", "infantry", "air", "naval", "subs")},
    **{f"class_{c}": (f"class_{c}", ("enemy_class", c), "cmd_special_lv") for c in ("commando", "engineer", "spy")},
    **{f"damage_{c}": (f"damage_{c}", ("damage_60s", c), "cmd_dmg_class_lv") for c in ("air", "land", "naval", "siege")},
    "outranged": ("outranged", ("defense_outranged_60s",), "cmd_special_lv"),
    "harvesters_lost": ("harvesters_lost", ("harvester_losses_60s",), "cmd_special_lv"),
    "silos": ("silos", ("silos",), "cmd_special_lv"),
    "open_back": ("open_back", ("open_back",), "cmd_special_lv"),
    "uncovered_buildings": ("uncovered_buildings", ("uncovered_buildings",), "cmd_special_lv"),
    "enemy_soft": ("enemy_soft", ("enemy_soft_buildings",), "cmd_tower_lv"),
    "towers_ground": ("towers_ground", ("own_defense", "ground"), "cmd_tower_lv"),
    "towers_anti_air": ("towers_anti_air", ("own_defense", "anti_air"), "cmd_tower_lv"),
}

SEKTOREN = ["none", "n", "ne", "e", "se", "s", "sw", "w", "nw"]
KATEGORIEN = {
    ("damage_from",): ["none", "air", "land", "naval", "siege"],
    ("damage_sector",): SEKTOREN,
    ("uncovered_sector",): SEKTOREN,
    ("missing_defense",): ["none", "anti_air", "ground"],
    ("open_back_sector",): SEKTOREN,
    ("ore_wasting",): ["False", "True"],
    ("enemy_base_known",): ["False", "True"],
    ("superweapon", "own"): ["none", "charging", "ready"],
    ("superweapon", "enemy"): ["none", "charging", "ready"],
    ("own_special", "commando"): LEVELS,
    ("own_special", "engineer"): LEVELS,
    ("own_special", "spy"): LEVELS,
}

FRAGEN = {
    "counter": ["none", "anti_air", "anti_siege_sortie", "spread_defense", "anti_infiltration", "anti_naval"],
    "defense_sector": SEKTOREN,
    "economy_fix": ["none", "silo", "refinery", "harvester"],
    "special_op": ["none", "commando_raid", "engineer_capture", "spy_infiltrate", "superweapon_now"],
}
QUANTILE = [10, 25, 50, 75, 90, 99]


def level_of(v: int, t: list[int]) -> str:

    if v <= 0:
        return "none"
    for k, name in enumerate(("low", "medium", "high")):
        if v < t[k]:
            return name
    return "strong"


def quantil(werte: list[int], q: int) -> int:

    if not werte:
        return 0
    s = sorted(werte)
    k = max(0, min(len(s) - 1, (q * len(s) + 99) // 100 - 1))
    return s[k]


def lese(pfade: list[str]) -> list[tuple[str, list[dict]]]:

    dateien: list[Path] = []
    for p in pfade or [str(ROOT / "build" / "ai_log")]:
        pp = Path(p)
        if pp.is_dir():
            dateien += sorted(pp.glob("*.jsonl"))
        elif pp.exists():
            dateien.append(pp)
    out = []
    for f in dateien:
        zeilen = []
        for line in f.read_text(encoding="utf-8").splitlines():
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if "summary" in d:
                zeilen.append(d)
        out.append((f.name, zeilen))
    return out


def stufe(summary: dict, pfad: tuple) -> str:
    v = summary
    for k in pfad:
        v = v.get(k, {}) if isinstance(v, dict) else {}
    return v if isinstance(v, str) else str(v)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pfade", nargs="*", help="Ordner oder .jsonl-Dateien (Vorgabe build/ai_log)")
    ap.add_argument("--karte", default="", help="nur dieser Kartentyp (land, mixed, islands)")
    ap.add_argument("--schwellen", nargs="*", default=[], metavar="MERKMAL=a,b,c",
                    help="Probeschwellen auf den Rohwerten auswerten")
    ap.add_argument("--quelle", default="bot", choices=["bot", "human", "alle"],
                    help="Zeilen der Bots (KOMMANDEUR), des Menschen (KOMMANDEUR-SPIELER) oder alle")
    ap.add_argument("--abdeckung", action="store_true",
                    help="nur die Abdeckung der Felder und Fragen aus §9 (welche Stufen/Optionen kamen vor)")
    a = ap.parse_args()

    probe: dict[str, list[int]] = {}
    for s in a.schwellen:
        k, _, v = s.partition("=")
        probe[k] = [int(x) for x in v.split(",")]

    dateien = lese(a.pfade)
    def passt(z: dict) -> bool:
        if a.karte and z.get("map_type") != a.karte:
            return False
        mensch = z.get("source") == "human"
        return a.quelle == "alle" or (a.quelle == "human") == mensch
    dateien = [(n, [z for z in zz if passt(z)]) for n, zz in dateien]
    zeilen = [z for _, zz in dateien for z in zz]
    mit_raw = [z for z in zeilen if isinstance(z.get("raw"), dict)]
    print(f"{len(dateien)} Dateien, {len(zeilen)} Zeilen ({a.quelle}), davon {len(mit_raw)} mit Rohwerten")
    if not zeilen:
        return 1
    if a.abdeckung:
        return abdeckung(zeilen)


    kopf = "Merkmal".ljust(15) + "".join(f"p{q}".rjust(8) for q in QUANTILE) + "   max".rjust(8) + "  =0 %".rjust(7)
    kopf += "  " + " ".join(n[:6].rjust(6) for n in LEVELS) + "   (Stufen in %)"
    print("\n" + kopf)
    for name, (rk, pfad, feld) in MERKMALE.items():
        werte = [int(z["raw"].get(rk, 0)) for z in mit_raw]
        stufen = Counter(stufe(z["summary"], pfad) for z in zeilen)
        n = sum(stufen.values())
        row = name.ljust(15)
        row += "".join(str(quantil(werte, q)).rjust(8) for q in QUANTILE)
        row += str(max(werte) if werte else 0).rjust(8)
        row += f"{(100 * sum(1 for w in werte if w <= 0) / len(werte)) if werte else 0:7.0f}"
        if name == "income":
            trend = "  " + " ".join(f"{k}={100 * stufen[k] / n:.0f}" for k in ("rising", "flat", "falling"))
            print(row + trend)
            continue
        row += "  " + " ".join(f"{100 * stufen[l] / n:6.1f}" for l in LEVELS)
        print(row)
        if name in probe and werte:
            neu = Counter(level_of(w, probe[name]) for w in werte)
            print("  probe".ljust(15) + f" {probe[name]}".ljust(62) +
                  "  " + " ".join(f"{100 * neu[l] / len(werte):6.1f}" for l in LEVELS))


    print("\nRegeln")
    wechsel = []
    for fname, zz in dateien:
        je_platz = defaultdict(list)
        for z in zz:
            if a.karte and z.get("map_type") != a.karte:
                continue
            je_platz[z.get("player")].append(z)
        for pl, rows in je_platz.items():
            rows.sort(key=lambda r: r.get("tick", 0))
            docs = [r.get("directive", {}).get("doctrine") for r in rows]
            n = sum(1 for i in range(1, len(docs)) if docs[i] != docs[i - 1])
            wechsel.append((fname, pl, n, Counter(docs)))
    for fname, pl, n, c in wechsel:
        print(f"  {fname} KI{pl}: {n} Doktrinwechsel {dict(c)}")

    def anteil(bed, ziel) -> str:
        sel = [z for z in zeilen if bed(z)]
        if not sel:
            return "0 Zeilen"
        treffer = sum(1 for z in sel if ziel(z))
        return f"{treffer}/{len(sel)} ({100 * treffer / len(sel):.0f} %)"

    st = lambda z: z.get("directive", {}).get("stance")
    eco = lambda z: z.get("directive", {}).get("economy")
    angriff = lambda z: bool(z["summary"].get("enemy", {}).get("attacking"))
    print("  Haltung gesamt:", dict(Counter(st(z) for z in zeilen)))
    print("  Wirtschaft gesamt:", dict(Counter(eco(z) for z in zeilen)))
    print("  defend, während die Basis angegriffen wird:", anteil(angriff, lambda z: st(z) == "defend"))
    print("  defend ohne Angriff:", anteil(lambda z: not angriff(z), lambda z: st(z) == "defend"))
    print("  defend bei base_damage_60s ab medium:",
          anteil(lambda z: LEVELS.index(z["summary"].get("base_damage_60s", "none")) >= 2, lambda z: st(z) == "defend"))
    print("  attack bei Landarmee ab high:",
          anteil(lambda z: LEVELS.index(z["summary"].get("army", {}).get("land", "none")) >= 3, lambda z: st(z) == "attack"))
    print("  retreat gesamt:", anteil(lambda z: True, lambda z: st(z) == "retreat"))
    fall = lambda z: z["summary"].get("income") == "falling" and bool(z["summary"].get("opening_done"))
    print("  more_refineries bei fallenden Einnahmen (nach der Eröffnung):", anteil(fall, lambda z: eco(z) == "more_refineries"))
    print("  more_refineries sonst:", anteil(lambda z: not fall(z), lambda z: eco(z) == "more_refineries"))
    print("  Rohwert-Regel „wenig Geld, Einnahmen fallen\":",
          anteil(lambda z: fall(z) and LEVELS.index(z["summary"].get("credits", "none")) <= 1,
                 lambda z: eco(z) == "more_refineries"))


    neu = [z for z in zeilen if "enemy_class" in z["summary"]]
    if neu:
        print("\nRegeln §9.3 (%d Zeilen mit Bedrohungsbild)" % len(neu))
        lv = lambda z, *p: LEVELS.index(stufe(z["summary"], p)) if stufe(z["summary"], p) in LEVELS else 0
        wahl = lambda z, q: str(z.get("directive", {}).get(q, "?"))
        zeilen_alt = zeilen
        zeilen = neu
        print("  anti_siege_sortie bei Belagerer ab medium und überreichtem Turm:",
              anteil(lambda z: lv(z, "enemy_class", "siege") >= 2 and lv(z, "defense_outranged_60s") >= 1,
                     lambda z: wahl(z, "counter") == "anti_siege_sortie"))
        print("  anti_air bei Luftangriff ohne Flak im Sektor:",
              anteil(lambda z: z["summary"].get("missing_defense") == "anti_air",
                     lambda z: wahl(z, "counter") == "anti_air"))
        print("  Sektor = ungedeckter Sektor:",
              anteil(lambda z: z["summary"].get("uncovered_sector", "none") != "none",
                     lambda z: wahl(z, "defense_sector") == z["summary"].get("uncovered_sector")))
        print("  silo bei vollem Lager:", anteil(lambda z: bool(z["summary"].get("ore_wasting")),
                                                 lambda z: wahl(z, "economy_fix") == "silo"))
        print("  superweapon_now bei eigener fertiger Superwaffe und bekannter Basis:",
              anteil(lambda z: stufe(z["summary"], ("superweapon", "own")) == "ready" and bool(z["summary"].get("enemy_base_known")),
                     lambda z: wahl(z, "special_op") == "superweapon_now"))
        print("  anti_infiltration bei gesehenem Kommando/Pionier/Spion:",
              anteil(lambda z: max(lv(z, "enemy_class", c) for c in ("commando", "engineer", "spy")) >= 1,
                     lambda z: wahl(z, "counter") == "anti_infiltration"))
        for q in FRAGEN:
            print(f"  {q} gesamt:", dict(Counter(wahl(z, q) for z in neu)))
        zeilen = zeilen_alt
    return 0


def abdeckung(zeilen: list[dict]) -> int:

    neu = [z for z in zeilen if "enemy_class" in z.get("summary", {})]
    print(f"\nAbdeckung §9: {len(neu)} Zeilen mit Bedrohungsbild")
    luecken = 0

    def zeile(name: str, werte: Counter, soll: list[str]) -> None:
        nonlocal luecken
        fehlt = [w for w in soll if werte.get(w, 0) == 0]
        luecken += len(fehlt)
        teile = " ".join(f"{w}={werte.get(w, 0)}" for w in soll)
        print(f"  {name:<34} {teile}" + (f"   FEHLT: {', '.join(fehlt)}" if fehlt else ""))

    print(" Stufen (Zusammenfassung):")
    for name, (_, pfad, _) in MERKMALE.items():
        if pfad[0] not in ("enemy_class", "damage_60s", "defense_outranged_60s", "harvester_losses_60s", "silos",
                           "open_back", "uncovered_buildings", "enemy_soft_buildings", "own_defense"):
            continue
        zeile(name, Counter(stufe(z["summary"], pfad) for z in neu), LEVELS)
    print(" Kategorien (Zusammenfassung):")
    for pfad, soll in KATEGORIEN.items():
        zeile(".".join(pfad), Counter(stufe(z["summary"], pfad) for z in neu), soll)
    print(" Fragen (directive, nach der Hysterese):")
    for q, soll in FRAGEN.items():
        zeile(q, Counter(str(z.get("directive", {}).get(q, "?")) for z in neu if q in z.get("directive", {})), soll)
    print(" Fragen (argmax der Entscheidung):")
    for q, soll in FRAGEN.items():
        c: Counter = Counter()
        for z in neu:
            d = z.get("decision", {}).get(q)
            if isinstance(d, dict) and d:
                c[max(d, key=d.get)] += 1
        zeile(q, c, soll)
    print(f"\n{luecken} Werte kamen nicht vor")
    return 0


if __name__ == "__main__":
    sys.exit(main())

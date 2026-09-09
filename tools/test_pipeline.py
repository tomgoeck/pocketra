#!/usr/bin/env python3

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rafmt.miniyaml import Rules, merge, parse, resolve_removals

ROOT = Path(__file__).resolve().parent.parent
MOD = ROOT / "reference" / "OpenRA" / "mods" / "ra"
ASSETS = ROOT / "game" / "assets"

failed = 0


def check(ok: bool, what: str) -> None:
    global failed
    if not ok:
        failed += 1
        print(f"FEHLER {what}")


def test_merge_keeps_removals() -> None:

    base = parse("A:\n\tX: 1\n")
    over = parse("A:\n\t-Y:\n")
    out = merge(base, over)
    keys = [c.key for c in out[0].children]
    check(keys == ["X", "-Y"], f"merge behält -Y (bekam {keys})")

    check([c.key for c in resolve_removals(out[0].children)] == ["X"], "resolve_removals wendet -Y an")

    rules = Rules([], ["^Soldier:\n\tCrushable:\n\t\tCrushClasses: infantry\n",
                       "E7:\n\tInherits: ^Soldier\n", "E7:\n\t-Crushable:\n"])
    e7 = rules.resolve("e7")
    check(e7 is not None and e7.child("Crushable") is None, "-Crushable entfernt den geerbten Trait")


def test_campaign_rules_reach_missions() -> None:

    if not MOD.exists():
        print("übersprungen: reference/OpenRA fehlt")
        return
    rules = json.loads((ASSETS / "rules.json").read_text())
    camp = rules.get("actors_campaign", {})
    check(bool(camp), "rules.json hat actors_campaign")
    check("crushable" in rules["actors"]["e7"], "Gefecht: E7 bleibt überfahrbar")
    check("crushable" not in camp.get("e7", {}), "Kampagne: E7 ist nicht überfahrbar (campaign-rules -Crushable)")
    check("crushable" not in camp.get("e7.noautotarget", {}), "Kampagne: Tanya (e7.noautotarget) nicht überfahrbar")
    check(camp.get("harv", {}).get("harvester", {}).get("search_from_proc") == 50,
          "Kampagne: HARV SearchFromProcRadius 50")


    m = json.loads((ASSETS / "maps" / "allies-10b.json").read_text())
    check(m.get("campaign") is True, "allies-10b ist als Kampagnenkarte markiert")
    check("e7" not in m.get("rules_override", {}).get("actors", {}),
          "allies-10b überschreibt e7 nicht selbst (deshalb braucht es actors_campaign)")

    over = m["rules_override"]["actors"]
    check(over["4tnk"]["mobile"]["locomotor"] == "heavytracked", "allies-10b: 4TNK heavytracked")


def test_map_removals_applied() -> None:

    maps = ASSETS / "maps"
    a02 = json.loads((maps / "allies-02.json").read_text())["rules_override"]["actors"]
    check("crushable" not in a02.get("e7", {}), "allies-02: E7 nicht überfahrbar")
    s07 = json.loads((maps / "soviet-07.json").read_text())["rules_override"]["actors"]
    check("auto_target" not in s07.get("pbox", {}), "soviet-07: PBOX ohne AutoTarget (-AutoTarget:)")


def test_cost_independent_of_buildable() -> None:

    rules = json.loads((ASSETS / "rules.json").read_text())["actors"]
    fact = rules["fact"]
    check(fact.get("cost") == 2000, "FACT hat Cost 2000")
    check(fact.get("sellable") is True, "FACT ist Sellable")
    check("disabled" in fact.get("buildable", {}).get("prerequisites", []), "FACT ist ~disabled")
    for name in ("hosp", "fcom", "miss", "oilb", "barl"):
        check(int(rules[name].get("cost", 0)) == 0 and not rules[name].get("sellable"),
              f"{name}: Zivilgebäude ohne Valued/Sellable")


def test_balance_overrides_applied() -> None:

    weapons = json.loads((ASSETS / "rules.json").read_text())["weapons"]
    check(weapons["155mm"].get("range") == 11776, "155mm Range 11c512 aus balance.yaml (12c0 − 0,5 Zellen)")
    check(weapons["155mm"].get("min_range") == 4096, "155mm MinRange bleibt 4c0 (OpenRA-Original)")
    check(weapons["scud"].get("range") == 10240, "SCUD (v2rl) unverändert bei 10c0")


def test_c4_vehicles_override() -> None:

    data = json.loads((ASSETS / "rules.json").read_text())
    actors = data["actors"]
    for name in ("3tnk", "1tnk", "apc", "harv", "mcv", "v2rl"):
        check(actors[name].get("demolishable") is True, f"{name} ist sprengbar (c4_vehicles)")
    for name in ("heli", "mig", "badr"):
        check(not actors[name].get("demolishable"), f"{name} (Flugzeug) bleibt unsprengbar")
    for name in ("dd", "ss", "ca"):
        check(not actors[name].get("demolishable"), f"{name} (Schiff) bleibt unsprengbar")
    check(actors["powr"].get("demolishable") is True, "Gebäude bleiben sprengbar (OpenRA ^Building)")
    check(actors["e7"].get("demolition_delay") == 45 and actors["volk"].get("demolition_delay") == 45,
          "Tanya und Volkov legen die Ladung (DetonationDelay 45)")


    missed: list[str] = []
    seen = 0
    for path in sorted((ASSETS / "maps").glob("*.json")):
        blob = json.loads(path.read_text())
        if not isinstance(blob, dict):
            continue
        rules = (blob.get("rules_override") or {}).get("actors") or {}
        for name, act in rules.items():
            tt = act.get("target_types") or []
            if "Vehicle" in tt and not act.get("building") and not act.get("aircraft"):
                seen += 1
                if not act.get("demolishable"):
                    missed.append(f"{path.name}:{name}")
    check(seen > 0, f"kartenlokale Fahrzeug-Deltas gefunden ({seen})")
    check(not missed, "kartenlokale Fahrzeuge behalten `demolishable` (%d Ausreißer: %s)"
          % (len(missed), missed[:5]))


def test_c4_bridges_override() -> None:

    data = json.loads((ASSETS / "rules.json").read_text())
    actors = data["actors"]
    bridges = [n for n, a in actors.items() if isinstance(a.get("bridge"), dict)]
    check(len(bridges) >= 5, f"Brückenspannen in rules.json gefunden ({len(bridges)})")
    missing = [n for n in bridges if not actors[n].get("demolishable")]
    check(not missing, "alle Brückenspannen sind sprengbar (fehlend: %s)" % missing[:5])
    rules_db = (ROOT / "game" / "scripts" / "game" / "rules_db.gd").read_text(encoding="utf-8")
    start = rules_db.index("func _build_bridge_type")
    end = rules_db.index("func _build_type", start)
    check('"demolishable"' in rules_db[start:end],
          "RulesDb._build_bridge_type reicht `demolishable` an die Sim weiter")


def test_type_fields_reach_sim() -> None:

    rules_db = (ROOT / "game" / "scripts" / "game" / "rules_db.gd").read_text(encoding="utf-8")
    proto = (ROOT / "game" / "scripts" / "proto" / "proto_world.gd").read_text(encoding="utf-8")
    bridge = (ROOT / "gdext" / "src" / "ra_sim.cpp").read_text(encoding="utf-8")


    start = bridge.index("int RaSim::define_type(")
    brace = bridge.index("{", start)
    depth = 0
    end = len(bridge)
    for n in range(brace, len(bridge)):
        if bridge[n] == "{":
            depth += 1
        elif bridge[n] == "}":
            depth -= 1
            if depth == 0:
                end = n
                break
    sim_keys = set(re.findall(r'def\.(?:get|has)\(\s*"([a-z0-9_]+)"', bridge[start:end]))


    db_keys = set(re.findall(r'\bt\["([a-z0-9_]+)"\]\s*=', rules_db))
    for tup in re.findall(r'_add_(?:facing_)?frame_list\(t,\s*"([a-z0-9_]+)"(?:,\s*"([a-z0-9_]+)")?', rules_db):
        db_keys.update(k for k in tup if k)


    fwd = set(re.findall(r'"([a-z0-9_]+)"\s*:', proto)) | set(re.findall(r'def\["([a-z0-9_]+)"\]', proto))
    for copy_list in re.findall(r"for key in \[(.*?)\]:", proto, re.S):
        fwd |= set(re.findall(r'"([a-z0-9_]+)"', copy_list))


    via_setter = {"husk_actor"}

    missing = sorted((sim_keys & db_keys) - fwd - via_setter)
    check(not missing, f"proto_world.gd reicht diese Typ-Felder nicht an die Sim weiter: {missing}")


def main() -> int:
    test_merge_keeps_removals()
    test_campaign_rules_reach_missions()
    test_map_removals_applied()
    test_cost_independent_of_buildable()
    test_balance_overrides_applied()
    test_c4_vehicles_override()
    test_c4_bridges_override()
    test_type_fields_reach_sim()
    if failed:
        print(f"{failed} Prüfung(en) fehlgeschlagen")
        return 1
    print("OK — Pipeline-Selbsttest bestanden")
    return 0


if __name__ == "__main__":
    sys.exit(main())

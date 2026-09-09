#!/usr/bin/env python3

from __future__ import annotations

import json
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


def main() -> int:
    test_merge_keeps_removals()
    test_campaign_rules_reach_missions()
    test_map_removals_applied()
    test_cost_independent_of_buildable()
    test_balance_overrides_applied()
    if failed:
        print(f"{failed} Prüfung(en) fehlgeschlagen")
        return 1
    print("OK — Pipeline-Selbsttest bestanden")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rafmt.miniyaml import Node, Rules, parse_file

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OPENRA = ROOT / "reference" / "OpenRA"
DEFAULT_OUT = ROOT / "game" / "assets" / "rules.json"


RULES_FORMAT = hashlib.sha1(Path(__file__).resolve().read_bytes()).hexdigest()[:12]


RULE_FILES = ["misc.yaml", "ai.yaml", "player.yaml", "palettes.yaml", "world.yaml", "defaults.yaml", "vehicles.yaml",
              "husks.yaml", "structures.yaml", "infantry.yaml", "civilian.yaml", "decoration.yaml", "aircraft.yaml",
              "ships.yaml", "fakes.yaml", "map-generators.yaml"]


CAMPAIGN_RULES = "campaign-rules.yaml"


BOT_TYPES = ("rush", "normal", "turtle", "naval")


VOLKOV_MAP = "soviet-soldier-volkov-n-chitzkoi"
VOLK_ACTOR = """VOLK:
\tInherits: E7
\tTooltip:
\t\tName: actor-volk-name
\tRenderSprites:
\t\tImage: GNRL
\tWithInfantryBody:
\t\tAttackSequences:
\t\t\tprimary: shoot
\tArmament@PRIMARY:
\t\tWeapon: VolkovWeapon
\tArmament@GARRISONED:
\t\tWeapon: VolkovWeapon
\tVoiced:
\t\tVoiceSet: GenericVoice
\t-AnnounceOnKill:
\tBuildable:
\t\tPrerequisites: ~barr, stek, ~techlevel.high
"""


def wdist(v: str) -> int:

    v = v.strip()
    if "c" in v:
        c, rest = v.split("c", 1)
        return int(c) * 1024 + (int(rest) if rest else 0)
    return int(v) if v else 0


def csv(v: str) -> list[str]:
    return [x.strip() for x in v.split(",") if x.strip()]


def ints(v: str) -> list[int]:
    return [wdist(x) for x in csv(v)]


def child_dict(n: Node | None) -> dict:
    return n.as_dict() if n is not None else {}


def load_fluent(path: Path) -> dict[str, dict[str, str]]:

    out: dict[str, dict[str, str]] = {}
    current = None
    if not path.exists():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^actor-([a-z0-9.\-]+)\s*=\s*(.*)$", line)
        if m:
            key = m.group(1)
            current = out.setdefault(key, {})
            if m.group(2).strip():
                current["name"] = m.group(2).strip()
            continue
        m = re.match(r"^\s+\.([a-z\-]+)\s*=\s*(.*)$", line)
        if m and current is not None:
            current[m.group(1)] = m.group(2).strip()
            continue
        if line and not line.startswith(" "):
            current = None
    return out


def extract_yaml_block(text: str, key: str) -> str:

    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if line == f"{key}:" or line.startswith(f"{key}: ")), None)
    if start is None:
        raise KeyError(f"{key!r} nicht gefunden")
    out = [lines[start]]
    for line in lines[start + 1:]:
        if line.strip() == "" or line[0] == "\t":
            out.append(line)
        else:
            break
    return "\n".join(out) + "\n"


def tileset_files(sq: Node, defaults_node: Node | None) -> dict[str, str]:

    node = sq.child("TilesetFilenames")
    if node is None and defaults_node is not None:
        node = defaults_node.child("TilesetFilenames")
    return {k.lower(): v.lower() for k, v in child_dict(node).items()} if node is not None else {}


def sequences(mod: Path) -> dict[str, dict[str, dict]]:

    out: dict[str, dict[str, dict]] = {}
    for f in sorted((mod / "sequences").glob("*.yaml")):
        nodes = list(parse_file(f))
        by_key = {n.key.lower(): n for n in nodes}
        for actor in nodes:

            base_key = actor.get("Inherits", "")
            if base_key and base_key.lower() in by_key:
                base = by_key[base_key.lower()]
                merged = {c.key: c for c in base.children}
                for c in actor.children:
                    merged[c.key] = c
                actor.children = list(merged.values())
            seqs: dict[str, dict] = {}
            defaults_node = actor.child("Defaults")
            defaults = child_dict(defaults_node)
            for sq in actor.children:
                if sq.key == "Defaults":
                    continue
                d = dict(defaults)
                d.update(sq.as_dict())
                length = d.get("Length", "1")
                frames_list = [int(x) for x in csv(str(d.get("Frames", "")))]
                file_field = str(d.get("Filename", f"{actor.key}.shp")).lower().split("|")[-1]


                combine_node = sq.child("Combine")
                if combine_node is not None and not frames_list:
                    parts = sorted(combine_node.children, key=lambda c: int(c.key) if c.key.isdigit() else 0)
                    combine_frames: list[int] = []
                    combine_file = ""
                    combine_ok = True
                    for part in parts:
                        pd = part.as_dict()
                        pf = str(pd.get("Filename", "")).lower().split("|")[-1]
                        if pf:
                            combine_file = pf
                        pframes = str(pd.get("Frames", ""))
                        if pframes:
                            combine_frames.extend(int(x) for x in csv(pframes))
                        elif str(pd.get("Length", "1")) == "*":
                            combine_ok = False
                            break
                        else:
                            pstart = int(pd.get("Start", 0))
                            plen = int(pd.get("Length", 1))
                            combine_frames.extend(range(pstart, pstart + plen))
                    if combine_ok and combine_frames:
                        frames_list = combine_frames
                        if combine_file:
                            file_field = combine_file
                seqs[sq.key] = {

                    "file": file_field,
                    "start": int(d.get("Start", 0)),
                    "length": -1 if length == "*" else int(length),
                    "facings": int(d.get("Facings", 1)),
                    "tick": int(d.get("Tick", 40)),
                    "stride": int(d.get("Stride", 0)),


                    "offset": (ints(str(d.get("Offset", "0,0"))) + [0, 0])[:2],
                    "classic": d.get("UseClassicFacings", "False") == "True",


                    "tileset_files": tileset_files(sq, defaults_node),
                    "frames": frames_list,
                }
            out[actor.key.lower()] = seqs
    return out


BALANCE_FILE = Path(__file__).resolve().parent / "balance.yaml"


BALANCE_WEAPON_FIELDS = {"Range": "range", "MinRange": "min_range"}


def apply_balance_overrides(wdict: dict[str, dict], path: Path = BALANCE_FILE) -> int:

    n = 0
    if not path.exists():
        return n
    for top in parse_file(path):
        if top.key != "weapons":
            continue
        for wnode in top.children:
            weapon = wdict.get(wnode.key)
            if weapon is None:
                print(f"balance.yaml: Waffe '{wnode.key}' unbekannt, übersprungen", file=sys.stderr)
                continue
            for f in wnode.children:
                field = BALANCE_WEAPON_FIELDS.get(f.key)
                if field is None:
                    print(f"balance.yaml: Feld '{f.key}' bei '{wnode.key}' nicht unterstützt", file=sys.stderr)
                    continue
                weapon[field] = wdist(f.value)
                n += 1
    return n


def extract_weapon(name: str, w: Node, seqs: dict[str, dict[str, dict]]) -> dict:
    d = w.as_dict()
    out = {
        "reload": int(d.get("ReloadDelay", 1)),
        "range": wdist(str(d.get("Range", "0"))),
        "report": [Path(x).stem.lower() for x in csv(str(d.get("Report", "")))],
        "burst": int(d.get("Burst", 1)),
        "burst_delays": ints(str(d.get("BurstDelays", "5"))),
        "min_range": wdist(str(d.get("MinRange", "0"))),
        "valid_targets": csv(str(d.get("ValidTargets", ""))),
        "invalid_targets": csv(str(d.get("InvalidTargets", ""))),
        "projectile": {"type": w.get("Projectile", "Bullet")},
        "warheads": [],
    }
    pj = w.child("Projectile")
    if pj is not None:
        pd = pj.as_dict()
        speed = str(pd.get("Speed", "0"))
        out["projectile"].update({
            "speed": wdist(csv(speed)[0]) if speed else 0,
            "image": str(pd.get("Image", "")).lower(),
            "inaccuracy": wdist(str(pd.get("Inaccuracy", "0"))),
            "blockable": pd.get("Blockable", "False") == "True",
        })


        if w.get("Projectile", "Bullet") == "Missile":
            out["projectile"].update({
                "missile": True,
                "turn_rate": int(pd.get("HorizontalRateOfTurn", "20") or 20),
                "range_limit": wdist(str(pd.get("RangeLimit", "0"))),
                "arm": int(pd.get("Arm", "0") or 0),
                "lock_on_probability": int(pd.get("LockOnProbability", "100") or 100),
                "lock_on_inaccuracy": wdist(str(pd.get("LockOnInaccuracy", "-1"))),
                "close_enough": wdist(str(pd.get("CloseEnough", "298"))),
                "trail_image": str(pd.get("TrailImage", "")).lower(),
                "trail_interval": int(pd.get("TrailInterval", "2") or 2),
            })


        img = out["projectile"]["image"]
        seq_names = csv(str(pd.get("Sequences", "idle"))) or ["idle"]
        sq = seqs.get(img, {}).get(seq_names[0]) if img else None
        if sq is not None:
            out["projectile"].update({
                "start": sq["start"], "facings": sq["facings"], "classic": sq["classic"],
            })
    for c in w.children:
        if not c.key.startswith("Warhead"):
            continue
        wd = c.as_dict()
        if c.value in ("SpreadDamage", "TargetDamage"):

            out["warheads"].append({
                "type": c.value,
                "damage": int(wd.get("Damage", 0)),
                "spread": wdist(str(wd.get("Spread", "43" if c.value == "SpreadDamage" else "0"))),
                "delay": int(wd.get("Delay", 0)),
                "versus": {k: int(v) for k, v in child_dict(c.child("Versus")).items()},
                "damage_types": csv(str(wd.get("DamageTypes", ""))),
                "falloff": ints(str(wd.get("Falloff", ""))) if wd.get("Falloff") else [],
                "valid_targets": csv(str(wd.get("ValidTargets", ""))),
                "invalid_targets": csv(str(wd.get("InvalidTargets", ""))),
            })
        elif c.value == "FireCluster":


            out["warheads"].append({
                "type": "FireCluster",
                "weapon": str(wd.get("Weapon", "")).lower(),
                "dimensions": ints(str(wd.get("Dimensions", "1,1"))),
                "footprint": str(wd.get("Footprint", "")),
            })
        elif c.value == "CreateEffect":
            out["warheads"].append({
                "type": "CreateEffect",
                "image": str(wd.get("Image", "explosion")).lower(),
                "explosions": csv(str(wd.get("Explosions", ""))),
                "impact_sounds": [Path(x).stem.lower() for x in csv(str(wd.get("ImpactSounds", "")))],
            })
        elif c.value == "DestroyResource":


            size = ints(str(wd.get("Size", "0")))
            out["warheads"].append({
                "type": "DestroyResource",
                "size": size[0] if size else 0,
                "delay": int(wd.get("Delay", 0)),
            })
    return out


def extract_actor(name: str, r: Node, seqs: dict, fluent: dict) -> dict:

    g = lambda trait, key, default="": (r.child(trait).get(key, default) if r.child(trait) else default)
    has = lambda trait: r.child(trait) is not None
    out: dict = {"name": name}
    names = fluent.get(name, {})
    out["display_name"] = names.get("name", name.upper())
    if names.get("description"):
        out["description"] = names["description"]

    b = r.child("Buildable")
    if b is not None:
        prereqs, not_prereqs, hidden = [], [], []
        for p in csv(b.get("Prerequisites")):


            tilde = p.startswith("~")
            p = p.lstrip("~")
            if tilde:
                hidden.append(p)
            if p.startswith("!"):
                not_prereqs.append(p[1:])
            else:
                prereqs.append(p)
        out["buildable"] = {
            "queue": csv(b.get("Queue")),
            "order": int(b.get("BuildPaletteOrder", "9999") or 9999),
            "prerequisites": prereqs,
            "prerequisites_not": not_prereqs,

            "prerequisites_hidden": hidden,
            "limit": int(b.get("BuildLimit", "0") or 0),

            "duration": int(b.get("BuildDuration", "-1") or -1),
            "duration_modifier": int(b.get("BuildDurationModifier", "60") or 60),
        }
    if has("Valued"):
        out["cost"] = int(g("Valued", "Cost", "0") or 0)
    if has("CustomSellValue"):
        out["sell_value"] = int(g("CustomSellValue", "Value", "0") or 0)
    if has("Health"):
        out["hp"] = int(g("Health", "HP", "1") or 1)
    if has("Armor"):
        out["armor"] = g("Armor", "Type", "None")
    if has("Mobile"):
        out["mobile"] = {
            "speed": int(g("Mobile", "Speed", "1") or 1),
            "locomotor": g("Mobile", "Locomotor", "tracked"),
            "turn_speed": int(g("Mobile", "TurnSpeed", "512") or 512),
        }
    if has("Aircraft"):

        ac = r.child("Aircraft")
        out["aircraft"] = {
            "cruise_altitude": wdist(str(ac.get("CruiseAltitude", "1280"))),
            "altitude_velocity": wdist(str(ac.get("AltitudeVelocity", "43"))),
            "speed": int(ac.get("Speed", "1") or 1),
            "turn_speed": int(ac.get("TurnSpeed", "512") or 512),
            "can_hover": (ac.get("CanHover", "false") or "false").lower() == "true",
            "vtol": (ac.get("VTOL", "false") or "false").lower() == "true",
            "idle_behavior": ac.get("IdleBehavior", "None"),
            "landable": csv(ac.get("LandableTerrainTypes", "")),
        }
    for c in r.children:

        if c.key == "AmmoPool" or c.key.startswith("AmmoPool@"):
            out["ammo_pool"] = {
                "ammo": int(c.get("Ammo", "1") or 1),
                "reload_delay": int(c.get("ReloadDelay", "50") or 50),
                "rearm_sound": Path(str(c.get("RearmSound", ""))).stem.lower(),
            }


    overlays = []
    for c in r.children:
        if c.key == "WithIdleOverlay" or c.key.startswith("WithIdleOverlay@"):
            overlays.append({"sequence": c.get("Sequence", "idle"),
                             "offset": ints(c.get("Offset", "0,0,0") or "0,0,0"),
                             "requires": c.get("RequiresCondition", "")})
    if overlays:
        out["idle_overlays"] = overlays
    if has("Rearmable"):
        out["rearm_actors"] = [x.lower() for x in csv(g("Rearmable", "RearmActors", ""))]
    if has("AttackAircraft"):

        out["attack"] = {"type": "aircraft",
                         "attack_type": g("AttackAircraft", "AttackType", "Default"),
                         "facing_tolerance": int(g("AttackAircraft", "FacingTolerance", "80") or 80)}
    if has("AttackBomber"):
        out["attack_bomber"] = True
    if has("Parachutable"):
        out["fall_rate"] = int(g("Parachutable", "FallRate", "13") or 13)
    if has("Turreted"):
        out["turret"] = {
            "turn_speed": int(g("Turreted", "TurnSpeed", "512") or 512),
            "initial_facing": int(g("Turreted", "InitialFacing", "0") or 0),
            "realign_delay": int(g("Turreted", "RealignDelay", "40") or 40),
        }
    arms = []
    for c in r.children:
        if c.key == "Armament" or c.key.startswith("Armament@"):
            ad = c.as_dict()
            arms.append({
                "name": ad.get("Name", "primary"),
                "weapon": ad.get("Weapon", "").lower(),
                "requires": ad.get("RequiresCondition", ""),


                "reloading_condition": ad.get("ReloadingCondition", ""),
                "turret": ad.get("Turret", "primary"),
                "local_offset": ad.get("LocalOffset", ""),
                "relationships": csv(ad.get("TargetRelationships", "Enemy")),
            })
    if arms:
        out["armaments"] = arms


    wib = r.child("WithInfantryBody")
    if wib is not None:
        das = wib.get("DefaultAttackSequence", "")
        if das:
            out["default_attack_sequence"] = das
        aseq_node = wib.child("AttackSequences")
        if aseq_node is not None:
            aseq = {c.key: csv(c.value) for c in aseq_node.children if csv(c.value)}
            if aseq:
                out["attack_sequences"] = aseq
    if has("AttackFrontal"):
        out["attack"] = {"type": "frontal", "facing_tolerance": int(g("AttackFrontal", "FacingTolerance", "128") or 128)}
    elif has("AttackTurreted"):
        out["attack"] = {"type": "turreted"}
    elif has("AttackOmni"):
        out["attack"] = {"type": "omni"}
    elif has("AttackGarrisoned"):
        out["attack"] = {"type": "garrisoned"}
    elif has("AttackCharges"):
        out["attack"] = {"type": "charges", "facing_tolerance": 1024}
    elif has("AttackTesla"):

        out["attack"] = {
            "type": "tesla", "facing_tolerance": 1024,
            "max_charges": int(g("AttackTesla", "MaxCharges", "1") or 1),
            "reload_delay": int(g("AttackTesla", "ReloadDelay", "120") or 120),
            "initial_charge_delay": int(g("AttackTesla", "InitialChargeDelay", "22") or 22),
            "charge_delay": int(g("AttackTesla", "ChargeDelay", "3") or 3),

            "charge_audio": Path(g("AttackTesla", "ChargeAudio", "") or "").stem.lower(),
        }
    elif has("AttackLeap"):


        gca = r.child("GrantConditionOnAttack")
        out["attack"] = {
            "type": "leap", "facing_tolerance": 1024,
            "leap_speed": wdist(g("AttackLeap", "Speed", "426")),
            "eat_delay": int(gca.get("RevokeDelay", "15") or 15) if gca is not None else 0,
        }
    if has("AutoTarget"):
        out["auto_target"] = g("AutoTarget", "InitialStance", "AttackAnything")
        out["auto_target_scan"] = int(g("AutoTarget", "ScanRadius", "0") or 0)


        prio = r.child("AutoTargetPriority@DEFAULT")
        if prio is not None:
            out["auto_target_valid"] = csv(prio.get("ValidTargets", ""))
    bld = r.child("Building")
    if bld is not None:
        out["building"] = {
            "footprint": bld.get("Footprint", "x"),
            "dimensions": ints(bld.get("Dimensions", "1,1")),
            "terrain_types": csv(bld.get("TerrainTypes", "")),
            "center_offset": ints(bld.get("LocalCenterOffset", "0,0,0")),
            "build_sounds": [Path(x).stem.lower() for x in csv(bld.get("BuildSounds", ""))],
        }


    ge = r.child("GainsExperience")
    if ge is not None:
        levels = sorted(int(k) for k in child_dict(ge.child("Conditions")))
        mods: dict[str, dict[str, int]] = {}
        heal: dict = {}
        for c in r.children:
            base = c.key.split("@", 1)[0]
            req = c.get("RequiresCondition", "").strip()
            lvl = 0
            m = re.match(r"rank-veteran\s*==\s*(\d+)$", req)
            if m:
                lvl = int(m.group(1))
            elif req == "rank-elite":
                lvl = len(levels)
            if lvl <= 0:
                continue
            if base in ("DamageMultiplier", "FirepowerMultiplier", "SpeedMultiplier", "ReloadDelayMultiplier"):
                mods.setdefault(str(lvl), {})[base] = int(c.get("Modifier", "100") or 100)
            elif base == "ChangesHealth":
                heal = {
                    "step": int(c.get("Step", "0") or 0),
                    "percentage_step": int(c.get("PercentageStep", "0") or 0),
                    "delay": int(c.get("Delay", "0") or 0),
                    "start_if_below": int(c.get("StartIfBelow", "100") or 100),
                    "damage_cooldown": int(c.get("DamageCooldown", "0") or 0),
                }
        out["gains_experience"] = {
            "levels": levels, "modifiers": mods, "self_healing": heal,
            "notification": ge.get("LevelUpNotification", ""),
            "image": ge.get("LevelUpImage", ""),
            "sequence": ge.get("LevelUpSequence", "levelup"),
        }
    if has("GivesExperience"):
        out["gives_experience"] = int(g("GivesExperience", "Experience", "-1") or -1)


    ch = r.child("ChangesHealth")
    if ch is not None and not ch.get("RequiresCondition", "").strip():
        out["self_healing"] = {
            "step": int(ch.get("Step", "0") or 0),
            "percentage_step": int(ch.get("PercentageStep", "0") or 0),
            "delay": int(ch.get("Delay", "5") or 5),
            "start_if_below": int(ch.get("StartIfBelow", "50") or 50),
            "damage_cooldown": int(ch.get("DamageCooldown", "0") or 0),
        }


    if has("Crate"):
        out["crate"] = {
            "duration": int(g("Crate", "Duration", "0") or 0),
            "terrain_types": csv(g("Crate", "TerrainTypes", "")),
        }
    crate_actions = []
    for c in r.children:
        base = c.key.split("@", 1)[0]
        if not base.endswith("CrateAction"):
            continue
        cd = c.as_dict()
        crate_actions.append({
            "action": base,
            "shares": int(cd.get("SelectionShares", "10") or 10),
            "no_base_shares": int(cd.get("NoBaseSelectionShares", "1000") or 1000),
            "amount": int(cd.get("Amount", "0") or 0),
            "levels": int(cd.get("Levels", "1") or 1),
            "weapon": cd.get("Weapon", "").lower(),
            "units": [u.lower() for u in csv(cd.get("Units", ""))],
            "factions": csv(cd.get("ValidFactions", "")),
            "prerequisites": csv(cd.get("Prerequisites", "")),
            "time_delay": int(cd.get("TimeDelay", "0") or 0),
            "sound": Path(cd.get("Sound", "")).stem.lower() if cd.get("Sound") else "",
            "notification": cd.get("Notification", ""),
            "image": cd.get("Image", "crate-effects"),
            "sequence": cd.get("Sequence", ""),
            "min_amount": int(cd.get("MinAmount", "1") or 1),
            "max_amount": int(cd.get("MaxAmount", "2") or 2),
            "max_value": int(cd.get("MaxDuplicateValue", "-1") or -1),
            "max_radius": int(cd.get("MaxRadius", "4") or 4),
        })
    if crate_actions:
        out["crate_actions"] = crate_actions
    if has("ScalePowerWithHealth"):
        out["scale_power_with_health"] = True

    for c in r.children:
        if c.key.startswith("GrantCondition@") and "lowpower" in c.get("RequiresCondition", ""):
            out["needs_power"] = True
    if has("BaseProvider"):
        out["base_provider"] = {"range": wdist(g("BaseProvider", "Range", "10c0") or "10c0")}
    if has("GivesBuildableArea"):
        out["gives_buildable_area"] = True


    if has("ProvidesRadar"):
        out["provides_radar"] = True
    if has("RequiresBuildableArea"):
        out["adjacent"] = int(g("RequiresBuildableArea", "Adjacent", "2") or 2)
    if has("Production"):
        out["produces"] = csv(g("Production", "Produces", ""))
    for c in r.children:

        if (c.key == "Exit" or c.key.startswith("Exit@")) and "exit" not in out:


            out["exit"] = {"cell": ints(c.get("ExitCell", "0,0") or "0,0"),
                            "facing": int(c.get("Facing", "0") or 0),
                            "offset": ints(c.get("SpawnOffset", "0,0,0") or "0,0,0")}
    if has("RallyPoint"):

        out["rally"] = ints(g("RallyPoint", "Path", "") or "")
    if has("Power"):
        out["power"] = int(g("Power", "Amount", "0") or 0)
    provides = []
    for c in r.children:
        if c.key == "ProvidesPrerequisite" or c.key.startswith("ProvidesPrerequisite@"):
            pd = c.as_dict()
            provides.append({"prerequisite": pd.get("Prerequisite", name), "factions": csv(pd.get("Factions", "")),
                             "requires": csv(pd.get("RequiresPrerequisites", ""))})
    if provides:
        out["provides"] = provides
    if has("Harvester"):
        h = r.child("Harvester")
        out["harvester"] = {
            "capacity": int(g("StoresResources", "Capacity", "20") or 20),
            "bale_load_delay": int(h.get("BaleLoadDelay", "4") or 4),
            "bale_unload_delay": int(h.get("BaleUnloadDelay", "4") or 4),
            "search_from_proc": int(h.get("SearchFromProcRadius", "24") or 24),
            "search_from_harv": int(h.get("SearchFromHarvesterRadius", "12") or 12),
            "facings": int(h.get("HarvestFacings", "0") or 0),
            "wait_duration": int(h.get("WaitDuration", "25") or 25),
            "resources": csv(h.get("Resources", "")),
        }
    if has("SeedsResource"):

        out["seeds_resource"] = {
            "type": g("SeedsResource", "ResourceType", "Ore"),
            "interval": int(g("SeedsResource", "Interval", "75") or 75),
            "max_range": int(g("SeedsResource", "MaxRange", "100") or 100),
        }
    if has("Refinery"):
        out["refinery"] = True
    if has("StoresPlayerResources"):
        out["storage"] = int(g("StoresPlayerResources", "Capacity", "0") or 0)
    if has("WithResourceLevelSpriteBody"):


        out["resource_level_sequence"] = g("WithResourceLevelSpriteBody", "Sequence", "idle")
        out["resource_level_stages"] = int(g("WithResourceLevelSpriteBody", "Stages", "10") or 10)
    if has("WithResourceStoragePipsDecoration"):


        out["resource_pips"] = int(g("WithResourceStoragePipsDecoration", "PipCount", "0") or 0)
    if has("DockHost"):
        out["dock"] = {"offset": ints(g("DockHost", "DockOffset", "0,0") or "0,0"), "angle": int(g("DockHost", "DockAngle", "0") or 0)}
    for c in r.children:
        if c.key == "FreeActor" or c.key.startswith("FreeActor@"):
            fd = c.as_dict()
            out["free_actor"] = {"actor": fd.get("Actor", "").lower(), "offset": ints(fd.get("SpawnOffset", "0,0") or "0,0"),
                                 "facing": int(fd.get("Facing", "0") or 0)}


    if has("Bridge"):
        br = {
            "template": int(g("Bridge", "Template", "0") or 0),
            "damaged_template": int(g("Bridge", "DamagedTemplate", "0") or 0),
            "destroyed_template": int(g("Bridge", "DestroyedTemplate", "0") or 0),
            "long": (g("Bridge", "Long", "false") or "false").lower() == "true",
        }
        if br["template"]:
            out["bridge"] = br

    if has("RepairsUnits"):
        out["repairs_units"] = {
            "hp_per_step": int(g("RepairsUnits", "HpPerStep", "10") or 10),
            "interval": int(g("RepairsUnits", "Interval", "24") or 24),
            "value_percent": int(g("RepairsUnits", "ValuePercentage", "20") or 20),
        }
    if has("RepairableBuilding"):
        out["repairable_building"] = {"step": int(g("RepairableBuilding", "RepairStep", "7") or 7)}
    if has("Repairable"):
        out["repairable"] = csv(g("Repairable", "RepairActors", ""))


    if has("RepairableNear"):
        out["repairable"] = csv(g("RepairableNear", "RepairActors", ""))
    if has("Sellable"):
        out["sellable"] = True
    if has("WithMakeAnimation"):
        out["make_animation"] = True
    if has("WithBuildingBib"):
        out["bib"] = {"minibib": g("WithBuildingBib", "HasMinibib", "false").lower() == "true"}
    if has("Selectable"):
        out["bounds"] = ints(g("Selectable", "Bounds", "1024,1024") or "1024,1024")
    if has("RenderSprites") and g("RenderSprites", "Image"):
        out["image"] = g("RenderSprites", "Image").lower()
    if has("Voiced"):
        out["voice"] = g("Voiced", "VoiceSet", "")


    vo: dict[str, str] = {}
    if has("Mobile") and g("Mobile", "Voice"):
        vo["move"] = g("Mobile", "Voice")
    if has("AttackMove") and g("AttackMove", "Voice"):
        vo["attack_move"] = g("AttackMove", "Voice")
    for trait in ("AttackLeap", "AttackFrontal", "AttackTurreted", "AttackOmni", "AttackCharges"):
        if has(trait) and g(trait, "Voice"):
            vo["attack"] = g(trait, "Voice")
    if has("Demolition"):
        vo["demolish"] = g("Demolition", "Voice", "Action") or "Action"
    for c in r.children:
        if c.key == "VoiceAnnouncement" or c.key.startswith("VoiceAnnouncement@"):
            if c.get("Voice"):
                vo["build"] = c.get("Voice")
        if c.key == "AnnounceOnKill" or c.key.startswith("AnnounceOnKill@"):
            vo["kill"] = c.get("Voice", "Kill") or "Kill"
            out["kill_voice_interval"] = int(c.get("Interval", "5000") or 5000)

    death_voices: dict[str, str] = {}
    for c in r.children:
        if c.key == "DeathSounds" or c.key.startswith("DeathSounds@"):
            voice = c.get("Voice", "Die") or "Die"
            types = csv(c.get("DeathTypes", ""))
            for t in types or ["*"]:
                death_voices[t] = voice
    if death_voices:
        out["death_voices"] = death_voices
    if vo:
        out["voice_overrides"] = vo


    for c in r.children:
        if c.key == "SoundOnDamageTransition" or c.key.startswith("SoundOnDamageTransition@"):
            dsnd = [Path(x).stem.lower() for x in csv(c.get("DamagedSounds", ""))]
            xsnd = [Path(x).stem.lower() for x in csv(c.get("DestroyedSounds", ""))]
            if dsnd:
                out["damaged_sounds"] = dsnd
            if xsnd:
                out["destroyed_sounds"] = xsnd
    for c in r.children:
        if c.key == "FireWarheadsOnDeath" or c.key.startswith("FireWarheadsOnDeath@"):
            out["death_weapon"] = c.get("Weapon", "").lower()
    if has("WithDeathAnimation"):
        wda = r.child("WithDeathAnimation")
        out["death_animation"] = {
            "sequence": wda.get("DeathSequence", "die"),
            "crushed": wda.get("CrushedSequence", ""),
            "suffix": wda.get("UseDeathTypeSuffix", "true").lower() == "true",
            "types": {k: int(v) for k, v in child_dict(wda.child("DeathTypes")).items()},
        }
    if has("Transforms"):
        out["transforms"] = {"into": g("Transforms", "IntoActor", "").lower(), "offset": ints(g("Transforms", "Offset", "0,0") or "0,0"),
                             "facing": int(g("Transforms", "Facing", "0") or 0)}


    target_types: list[str] = []
    airborne_types: list[str] = []
    underwater_types: list[str] = []
    damaged_types: list[str] = []
    for c in r.children:
        if c.key != "Targetable" and not c.key.startswith("Targetable@"):
            continue
        cond = c.get("RequiresCondition", "")
        types_here = csv(c.get("TargetTypes", ""))


        if "damaged" in cond:
            damaged_types += types_here
        elif cond.strip() == "airborne":
            airborne_types += [t for t in types_here if t not in airborne_types]
        elif cond.strip() == "underwater":

            underwater_types += [t for t in types_here if t not in underwater_types]
        else:
            target_types += [t for t in types_here if t not in target_types]
    if target_types:
        out["target_types"] = target_types
    if airborne_types:
        out["target_types_airborne"] = airborne_types
    if underwater_types:
        out["target_types_underwater"] = underwater_types
    if damaged_types:
        out["target_types_damaged"] = damaged_types
    if has("MustBeDestroyed"):
        out["must_be_destroyed"] = g("MustBeDestroyed", "RequiredForShortGame", "false").lower() == "true"
    if has("Wall") or has("WithWallSpriteBody") or has("LineBuild"):
        out["wall"] = True
    if has("Husk"):
        out["husk"] = True
    if has("Cloak"):

        out["cloak"] = {
            "initial_delay": int(g("Cloak", "InitialDelay", "10") or 10),
            "cloak_delay": int(g("Cloak", "CloakDelay", "30") or 30),
            "detection_types": csv(g("Cloak", "DetectionTypes", "Cloak") or "Cloak"),
            "uncloak_on": csv(g("Cloak", "UncloakOn", "Attack") or "Attack"),
        }
    if has("DetectCloaked"):

        out["detect_cloaked"] = {
            "range": wdist(g("DetectCloaked", "Range", "5c0") or "5c0"),
            "types": csv(g("DetectCloaked", "DetectionTypes", "Cloak") or "Cloak"),
        }
    if has("Mine"):

        out["mine"] = {
            "crush_classes": csv(g("Mine", "CrushClasses", "mine") or "mine"),
            "detonate_classes": csv(g("Mine", "DetonateClasses", "mine") or "mine"),
        }
    if has("MineImmune"):
        out["mine_immune"] = True
    if has("Minelayer"):

        out["minelayer"] = {"mine": str(g("Minelayer", "Mine", "minv") or "minv").lower()}


    for c in r.children:
        kind = ""
        if c.key.startswith("GrantExternalConditionPower"):
            kind = "ironcurtain"
        elif c.key.startswith("ChronoshiftPower"):
            kind = "chronoshift"
        elif c.key.startswith("NukePower"):
            kind = "nuke"
        elif c.key.startswith("GpsPower"):
            kind = "gps"
        if not kind:
            continue
        dims = csv(c.get("Dimensions", "") or "")
        out["support_power"] = {
            "kind": kind,
            "charge_interval": int(c.get("ChargeInterval", "0") or 0),
            "duration": int(c.get("Duration", "0") or 0),
            "dimensions": [int(dims[0]), int(dims[1])] if len(dims) == 2 else [1, 1],
            "footprint": str(c.get("Footprint", "") or ""),
            "on_fire_sound": Path(str(c.get("OnFireSound", "") or "")).stem.lower(),
            "missile_weapon": str(c.get("MissileWeapon", "") or "").lower(),
            "missile_delay": int(c.get("MissileDelay", "0") or 0),
            "flight_delay": int(c.get("FlightDelay", "400") or 400),
            "begin_notification": str(c.get("BeginChargeSpeechNotification", "") or ""),
            "end_notification": str(c.get("EndChargeSpeechNotification", "") or ""),


            "launch_notification": str(c.get("LaunchSpeechNotification", "") or ""),
            "reveal_delay": int(c.get("RevealDelay", "0") or 0),
            "one_shot": (c.get("OneShot", "false") or "false").lower() == "true",
        }
    if has("CashTrickler"):

        out["cash_trickler"] = {
            "interval": int(g("CashTrickler", "Interval", "50") or 50),
            "amount": int(g("CashTrickler", "Amount", "15") or 15),
        }
    if has("Captures"):

        out["captures"] = True
        out["capture_types"] = csv(g("Captures", "CaptureTypes", "") or "")
        out["capture_delay"] = int(g("Captures", "CaptureDelay", "0") or 0)
    if has("Capturable"):
        out["capturable"] = True
        out["capturable_types"] = csv(g("Capturable", "Types", "") or "")

    if has("InstantlyRepairs"):
        out["instantly_repairs"] = True
    if has("InstantlyRepairable"):
        out["instantly_repairable"] = True
    if has("Demolition"):

        out["demolition_delay"] = int(g("Demolition", "DetonationDelay", "45") or 45)
    if has("Demolishable"):
        out["demolishable"] = True
    if has("Infiltrates"):

        out["infiltrates"] = csv(g("Infiltrates", "Types", "") or "")
    if has("ProducibleWithLevel"):


        pw = r.child("ProducibleWithLevel")
        out["producible_prereqs"] = csv(pw.get("Prerequisites", "") or "")
        out["producible_levels"] = int(pw.get("InitialLevels", "1") or 1)
    if has("Disguise"):
        out["disguise"] = True
    if has("IgnoresDisguise"):
        out["ignores_disguise"] = True

    if has("InfiltrateForCash"):
        c = r.child("InfiltrateForCash")
        out["infil_cash"] = csv(c.get("Types", "") or "")
        out["infil_cash_percent"] = int(c.get("Percentage", "100") or 100)
        out["infil_cash_min"] = int(c.get("Minimum", "-1") or -1)
    if has("InfiltrateForExploration"):
        out["infil_explore"] = csv(g("InfiltrateForExploration", "Types", "") or "")
    if has("InfiltrateForPowerOutage"):
        c = r.child("InfiltrateForPowerOutage")
        out["infil_power"] = csv(c.get("Types", "") or "")
        out["infil_power_duration"] = int(c.get("Duration", "500") or 500)
    if has("InfiltrateForSupportPower"):
        c = r.child("InfiltrateForSupportPower")
        out["infil_support"] = csv(c.get("Types", "") or "")
        out["infil_proxy"] = str(c.get("Proxy", "") or "").lower()
    if has("Cargo"):

        out["cargo"] = int(g("Cargo", "MaxWeight", "0") or 0)
        out["cargo_initial"] = [x.lower() for x in csv(g("Cargo", "InitialUnits", ""))]
        out["cargo_types"] = csv(g("Cargo", "Types", ""))
        out["cargo_delays"] = [int(g("Cargo", "BeforeUnloadDelay", "8") or 8),
                               int(g("Cargo", "BetweenUnloadDelay", "0") or 0),
                               int(g("Cargo", "AfterUnloadDelay", "25") or 25)]
        out["cargo_eject_on_death"] = (g("Cargo", "EjectOnDeath", "false") or "false").lower() == "true"
    if has("Passenger"):

        out["passenger"] = {"type": g("Passenger", "CargoType", ""), "weight": int(g("Passenger", "Weight", "1") or 1)}
    if has("Crushable"):

        out["crushable"] = {
            "classes": csv(g("Crushable", "CrushClasses", "infantry") or "infantry"),
            "sound": Path(str(g("Crushable", "CrushSound", ""))).stem.lower(),
        }
    if has("TakeCover"):

        out["take_cover"] = {
            "duration": int(g("TakeCover", "Duration", "100") or 100),
            "speed": int(g("TakeCover", "SpeedModifier", "50") or 50),
        }
    if has("HitShape"):
        hs = r.child("HitShape")
        ty = hs.child("Type")
        shape = {"type": (ty.value if ty is not None and ty.value else "Circle")}
        if ty is not None:
            if ty.get("Radius"):
                shape["radius"] = wdist(ty.get("Radius"))
            if ty.get("TopLeft"):
                shape["top_left"] = ints(ty.get("TopLeft"))
                shape["bottom_right"] = ints(ty.get("BottomRight", "512,512"))
        out["hit_shape"] = shape
    if has("RevealsShroud"):
        out["reveals"] = wdist(g("RevealsShroud", "Range", "0") or "0")
    if has("Infantry") or (r.child("Mobile") is not None and g("Mobile", "Locomotor", "") == "foot"):
        out["infantry"] = True
    if has("Interactable") and not has("Selectable"):
        out["interactable_only"] = True
    if has("Tooltip"):
        gn = g("Tooltip", "GenericName", "")
        if gn:
            out["generic_name"] = gn
    out["sequences"] = seqs.get(out.get("image", name), seqs.get(name, {}))
    return out


def supported(a: dict, weapons: dict[str, dict]) -> tuple[bool, str]:

    if a.get("attack_bomber"):
        return False, "attack-bomber"


    if a.get("produces") and not any(q in ("Building", "Defense", "Infantry", "Vehicle", "Aircraft",
                                           "Ship", "Boat", "Submarine")
                                     for q in a["produces"]):
        return False, "produces-unsupported"
    if a.get("husk"):
        return False, "husk"


    if "." in a["name"]:
        return False, "variant"
    return True, ""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--openra", type=Path, default=DEFAULT_OPENRA)
    a = ap.parse_args()
    mod = a.openra / "mods" / "ra"


    volkov_weapon_text = extract_yaml_block(
        (mod / "maps" / VOLKOV_MAP / "weapons.yaml").read_text(encoding="utf-8"), "VolkovWeapon")
    rules = Rules([mod / "rules" / f for f in RULE_FILES if (mod / "rules" / f).exists()],
                  extra_texts=[VOLK_ACTOR])
    weapons = Rules(sorted((mod / "weapons").glob("*.yaml")), extra_texts=[volkov_weapon_text])
    seqs = sequences(mod)
    fluent = load_fluent(mod / "fluent" / "rules.ftl")


    fluent["volk"] = {"name": "Volkov"}

    wdict: dict[str, dict] = {}
    for name in weapons.names():
        w = weapons.resolve(name)
        if w is not None:
            wdict[name] = extract_weapon(name, w, seqs)
    n_balance = apply_balance_overrides(wdict)

    campaign = Rules([mod / "rules" / f for f in RULE_FILES + [CAMPAIGN_RULES] if (mod / "rules" / f).exists()])

    actors: dict[str, dict] = {}
    for name in rules.names():
        r = rules.resolve(name)
        if r is None or name in ("player", "world", "editorworld"):
            continue
        act = extract_actor(name, r, seqs, fluent)
        if name == "volk":


            act["sequences"] = dict(act["sequences"])
            act["sequences"]["icon"] = {"file": "volkicon.shp", "start": 0, "length": 1, "facings": 1,
                                         "tick": 40, "stride": 0, "offset": [0, 0], "classic": False,
                                         "tileset_files": {}, "frames": []}
        ok, why = supported(act, wdict)
        act["supported"] = ok
        if not ok:
            act["unsupported_reason"] = why
        actors[name] = act


    for name in campaign.names():
        if not name.endswith(".noautotarget"):
            continue
        r = campaign.resolve(name)
        if r is None:
            continue
        act = extract_actor(name, r, seqs, fluent)
        base = name.split(".")[0]
        if not act.get("sequences"):
            act["sequences"] = seqs.get(base, {})
            act["image"] = base
        act["display_name"] = actors.get(base, {}).get("display_name", base.upper())
        act.pop("buildable", None)
        act["supported"] = True
        actors[name] = act


    campaign_names: set[str] = set()
    campaign_tpl: set[str] = set()
    for n in parse_file(mod / "rules" / CAMPAIGN_RULES):
        key = n.key.lower()
        if key.startswith("^"):
            campaign_tpl.add(key)
        elif key not in ("player", "world", "editorworld"):
            campaign_names.add(key)
    if campaign_tpl:
        for name in campaign.names():
            if campaign.inherits_from(name, campaign_tpl):
                campaign_names.add(name)
    actors_campaign: dict[str, dict] = {}
    for name in sorted(campaign_names):
        r = campaign.resolve(name)
        if r is None:
            continue
        act = extract_actor(name, r, seqs, fluent)
        base = actors.get(name, {})
        if not act.get("sequences") and "." in name:
            act["sequences"] = seqs.get(name.split(".")[0], {})
            act["image"] = name.split(".")[0]


        if act.get("display_name", "") == name.upper():
            inherited = base.get("display_name") or actors.get(name.split(".")[0], {}).get("display_name")
            if inherited:
                act["display_name"] = inherited
        act["supported"] = base.get("supported", supported(act, wdict)[0])
        actors_campaign[name] = act


    effects: dict[str, dict] = {}
    for image, sq in seqs.items():
        for sname, sd in sq.items():
            effects[f"{image}/{sname}"] = sd

    voices: dict[str, dict] = {}
    for vs in parse_file(mod / "audio" / "voices.yaml"):
        d = {"variants": {k: csv(v) for k, v in child_dict(vs.child("Variants")).items()},
             "voices": {k: csv(v) for k, v in child_dict(vs.child("Voices")).items()},
             "disable_variants": csv(vs.get("DisableVariants", ""))}
        voices[vs.key] = d


    notifications: dict[str, str] = {}
    notification_factions: dict[str, dict[str, str]] = {}
    ui_sounds: dict[str, str] = {}
    for n in parse_file(mod / "audio" / "notifications.yaml"):
        for c in n.children:
            if c.key != "Notifications":
                continue
            target = ui_sounds if n.key == "Sounds" else notifications
            for e in c.children:
                if "." in e.key and n.key == "Speech":
                    base, faction = e.key.split(".", 1)
                    notification_factions.setdefault(base, {})[faction] = e.value
                else:
                    target[e.key] = e.value


    sprite_files: set[str] = set()
    tileset_sprites: dict[str, set[str]] = {"temperat": set(), "snow": set(), "interior": set(), "desert": set()}
    for act in actors.values():
        if not act["supported"]:
            continue
        for sd in act.get("sequences", {}).values():
            if sd["file"].endswith((".tem", ".sno", ".int", ".des")) or sd["tileset_files"]:
                for ts in tileset_sprites:
                    tileset_sprites[ts].add(sd["tileset_files"].get(ts, sd["file"]))
            else:
                sprite_files.add(sd["file"])
    for eff in effects.values():
        if not eff["tileset_files"] and eff["file"] and not eff["file"].endswith((".tem", ".sno", ".int", ".des")):
            sprite_files.add(eff["file"])
    for w in wdict.values():
        img = w["projectile"].get("image", "")
        if img:
            sprite_files.add(img + ".shp" if not img.endswith(".shp") else img)


    ai_bots: dict[str, dict] = {}
    for bot in BOT_TYPES:
        ai_bots[bot] = {"building_fractions": {}, "building_limits": {}, "building_delays": {},
                        "units_to_build": {}, "unit_limits": {}, "exclude_from_squads": [], "params": {}}
    for n in parse_file(mod / "rules" / "ai.yaml"):
        for c in n.children:
            module = c.key.split("@", 1)[0]
            cond = c.get("RequiresCondition", "")
            for bot, out in ai_bots.items():

                if cond and f"enable-{bot}-ai" not in cond:
                    continue
                p = out["params"]
                if module == "BaseBuilderBotModule":
                    out["building_fractions"] = {k.lower(): int(v) for k, v in child_dict(c.child("BuildingFractions")).items()}
                    out["building_limits"] = {k.lower(): int(v) for k, v in child_dict(c.child("BuildingLimits")).items()}
                    out["building_delays"] = {k.lower(): int(v) for k, v in child_dict(c.child("BuildingDelays")).items()}
                    for key, name in (("MinimumExcessPower", "min_excess_power"), ("MaximumExcessPower", "max_excess_power"),
                                      ("ExcessPowerIncrement", "excess_power_increment"),
                                      ("ExcessPowerIncreaseThreshold", "excess_power_threshold"),
                                      ("InititalMinimumRefineryCount", "initial_min_refineries"),
                                      ("AdditionalMinimumRefineryCount", "additional_min_refineries"),
                                      ("NewProductionCashThreshold", "new_production_cash_threshold")):
                        if c.get(key):
                            p[name] = int(c.get(key))
                elif module == "UnitBuilderBotModule":
                    out["units_to_build"] = {k.lower(): int(v) for k, v in child_dict(c.child("UnitsToBuild")).items()}
                    out["unit_limits"] = {k.lower(): int(v) for k, v in child_dict(c.child("UnitLimits")).items()}
                elif module == "SquadManagerBotModule":
                    out["exclude_from_squads"] = [x.lower() for x in csv(c.get("ExcludeFromSquadsTypes", ""))]
                    for key, name in (("SquadSize", "squad_size"), ("RushInterval", "rush_interval"),
                                      ("MinimumAttackForceDelay", "min_attack_force_delay"),
                                      ("AttackForceInterval", "attack_force_interval"),
                                      ("ProtectUnitScanRadius", "protect_unit_scan_radius"),
                                      ("ProtectionScanRadius", "protection_scan_radius")):
                        if c.get(key):
                            p[name] = int(c.get(key))
                elif module == "HarvesterBotModule":
                    if c.get("InitialHarvesters"):
                        p["initial_harvesters"] = int(c.get("InitialHarvesters"))
                elif module == "McvExpansionManagerBotModule":
                    if c.get("MinimumConstructionYardCount"):
                        p["min_construction_yards"] = int(c.get("MinimumConstructionYardCount"))


    for out in ai_bots.values():
        for table in ("building_fractions", "units_to_build"):
            for name in list(out[table]):
                if name in actors and not actors[name]["supported"]:
                    del out[table][name]


        for name in ("mslo", "hpad", "afld", "syrd", "spen"):
            out["building_fractions"].pop(name, None)
        for name in ("ss", "msub", "dd", "ca", "pt", "lst"):
            out["units_to_build"].pop(name, None)
    ai: dict = {k: v for k, v in ai_bots["normal"].items() if k != "params"}
    ai["bots"] = ai_bots


    lua_messages: dict[str, str] = {}
    ftl = mod / "fluent" / "lua.ftl"
    if ftl.exists():
        key = None
        for line in ftl.read_text(encoding="utf-8").splitlines():
            m = re.match(r"^([a-z0-9\-]+)\s*=\s*(.*)$", line)
            if m:
                key = m.group(1)
                lua_messages[key] = m.group(2).strip()
            elif key and line.startswith("    "):
                lua_messages[key] = (lua_messages[key] + "\n" + line.strip()).strip()
            else:
                key = None


    music: dict = {"hidden": [], "volume": {}, "victory": "", "defeat": ""}
    for n in parse_file(mod / "audio" / "music.yaml"):
        d = n.as_dict()
        if d.get("Hidden", "").lower() == "true":
            music["hidden"].append(n.key)
        if d.get("VolumeModifier"):
            music["volume"][n.key] = float(d["VolumeModifier"])

    world_rules: dict = {}
    for n in parse_file(mod / "rules" / "world.yaml"):
        for c in n.children:
            if c.key == "MusicPlaylist":
                music["victory"] = c.get("VictoryMusic", "")
                music["defeat"] = c.get("DefeatMusic", "")
            if c.key == "CrateSpawner":
                world_rules["crate_spawner"] = {
                    "minimum": int(c.get("Minimum", "1") or 1),
                    "maximum": int(c.get("Maximum", "255") or 255),
                    "spawn_interval": int(c.get("SpawnInterval", "4500") or 4500),
                    "initial_delay": int(c.get("InitialSpawnDelay", "0") or 0),
                    "valid_ground": csv(c.get("ValidGround", "Clear,Rough,Road,Ore,Beach")),
                    "crate_actors": [x.lower() for x in csv(c.get("CrateActors", "crate"))],
                    "enabled": (c.get("CheckboxEnabled", "true") or "true").lower() != "false",
                }

    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps({
        "rules_format": RULES_FORMAT,
        "actors": actors, "actors_campaign": actors_campaign,
        "weapons": wdict, "effects": effects, "voices": voices, "notifications": notifications,
        "notification_factions": notification_factions, "ui_sounds": ui_sounds, "music": music, "ai": ai,
        "world": world_rules, "lua_messages": lua_messages,
    }, separators=(",", ":"), ensure_ascii=False))
    n_sup = sum(1 for x in actors.values() if x["supported"])
    print(f"{len(actors)} Actors ({n_sup} unterstützt), {len(wdict)} Waffen ({n_balance} Balance-Feld"
          f"{'er' if n_balance != 1 else ''} aus balance.yaml überschrieben), {len(effects)} Effektsequenzen, "
          f"{len(voices)} Stimmsätze, {len(sprite_files)} Sprite-Dateien → {a.out}")
    lines = ["# Erzeugt von tools/rules2json.py — Sprites aller unterstützten Actors, Effekte, Projektile",
             "# Zeilen mit @tileset gelten nur für diesen Atlas"]
    lines += sorted(sprite_files)
    for ts, files in tileset_sprites.items():
        lines += [f"@{ts} {f}" for f in sorted(files)]
    (Path(__file__).resolve().parent / "unit_sprites.txt").write_text("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

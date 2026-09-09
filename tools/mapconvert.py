#!/usr/bin/env python3

from __future__ import annotations

import argparse
import base64
import io
import json
import re
import struct
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rafmt.miniyaml import Node, Rules, parse
from rules2json import RULE_FILES, RULES_FORMAT, extract_actor, extract_weapon, load_fluent, sequences

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "game" / "assets" / "maps"
DEFAULT_OPENRA = ROOT / "reference" / "OpenRA"


DEFAULT_EXTRA = ROOT / "tools" / "maps_extra"


def read_map(entry: Path) -> tuple[str, bytes, bytes | None, dict[str, str]]:

    extras: dict[str, str] = {}
    if entry.is_dir():
        yaml = (entry / "map.yaml").read_text(encoding="utf-8", errors="replace")
        binary = (entry / "map.bin").read_bytes()
        png = (entry / "map.png").read_bytes() if (entry / "map.png").exists() else None
        for f in entry.iterdir():
            if f.suffix in (".lua", ".yaml", ".ftl") and f.name != "map.yaml":
                extras[f.name] = f.read_text(encoding="utf-8", errors="replace")
    else:
        with zipfile.ZipFile(entry) as z:
            yaml = z.read("map.yaml").decode("utf-8", errors="replace")
            binary = z.read("map.bin")
            png = z.read("map.png") if "map.png" in z.namelist() else None
            for n in z.namelist():
                if (n.endswith(".lua") or n.endswith(".yaml") or n.endswith(".ftl")) and n != "map.yaml" and "/" not in n:
                    extras[n] = z.read(n).decode("utf-8", errors="replace")
    return yaml, binary, png, extras


def parse_bin(binary: bytes, width: int, height: int) -> tuple[bytes, bytes]:
    s = io.BytesIO(binary)

    fmt = s.read(1)[0]
    w, h = struct.unpack("<HH", s.read(4))
    if (w, h) != (width, height):
        raise ValueError(f"map.bin {w}×{h} passt nicht zu MapSize {width}×{height}")
    if fmt == 1:
        tiles_off, heights_off, res_off = 5, 0, 3 * width * height + 5
    elif fmt == 2:
        tiles_off, heights_off, res_off = struct.unpack("<III", s.read(12))
    else:
        raise ValueError(f"unbekanntes map.bin-Format {fmt}")
    del heights_off
    tiles = bytearray(width * height * 3)
    resources = bytearray(width * height * 2)
    if tiles_off > 0:
        s.seek(tiles_off)

        for i in range(width):
            for j in range(height):
                tile, index = struct.unpack("<HB", s.read(3))
                if index == 255:
                    index = (i % 4 + j % 4 * 4)
                k = (j * width + i) * 3
                tiles[k:k + 3] = struct.pack("<HB", tile, index)
    if res_off > 0:
        s.seek(res_off)
        for i in range(width):
            for j in range(height):
                t, d = struct.unpack("<BB", s.read(2))
                k = (j * width + i) * 2
                resources[k] = t
                resources[k + 1] = d
    return bytes(tiles), bytes(resources)


VIDEO_KEYS = {"BackgroundVideo": "background", "BriefingVideo": "briefing", "StartVideo": "start",
              "WinVideo": "win", "LossVideo": "loss"}


def slug_for(stem: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", stem.lower()).strip("-")


def mission_rules(extras: dict[str, str]) -> dict:

    out: dict = {}
    for fname, text in extras.items():
        if not fname.endswith("rules.yaml"):
            continue
        for n in parse(text):
            if n.key == "Player":
                cash = n.path("PlayerResources", "DefaultCash")
                if cash is not None and cash.value:
                    out["default_cash"] = int(cash.value)

                gd = n.path("MissionObjectives", "GameOverDelay")
                if gd is not None and gd.value:
                    out["game_over_delay"] = int(gd.value)
            if n.key != "World":
                continue
            md = n.child("MissionData")
            if md is not None:
                videos = {}
                for key, short in VIDEO_KEYS.items():
                    v = md.get(key, "")
                    if v:
                        videos[short] = v.lower().removesuffix(".vqa")
                out["mission_data"] = {"briefing": md.get("Briefing", ""), "videos": videos}


            sg = n.path("StartGameNotification", "Notification")
            if sg is not None and sg.value:
                out["start_notification"] = sg.value
            tl = n.child("TimeLimitManager")
            if tl is not None:
                out["time_limit"] = {
                    "countdown_text": tl.get("CountdownText", ""),
                    "notification": tl.get("Notification", ""),
                    "skip_expired": tl.get("SkipTimerExpiredNotification", "").lower() == "true",
                    "limit": int(tl.get("TimeLimit", "0") or 0),
                }
            for c in n.children:
                if c.key.startswith("ScriptLobbyDropdown") and c.get("ID") == "difficulty":
                    vals = c.child("Values")
                    out["difficulties"] = [x.key for x in vals.children] if vals is not None else []
                    out["difficulty_default"] = c.get("Default", "normal")
    return out


_BASE: dict = {}


def base_rules(mod: Path) -> dict:

    if not _BASE:
        _BASE["files"] = [mod / "rules" / f for f in RULE_FILES if (mod / "rules" / f).exists()]
        _BASE["campaign"] = [mod / "rules" / "campaign-rules.yaml"] if (mod / "rules" / "campaign-rules.yaml").exists() else []
        _BASE["weapons"] = sorted((mod / "weapons").glob("*.yaml"))
        _BASE["seqs"] = sequences(mod)
        _BASE["fluent"] = load_fluent(mod / "fluent" / "rules.ftl")
    return _BASE


def map_rules_override(extras: dict[str, str], mod: Path, campaign: bool) -> dict:

    rules_texts = [t for n, t in sorted(extras.items()) if n.endswith("rules.yaml")]
    weapon_texts = [t for n, t in sorted(extras.items()) if n.endswith("weapons.yaml")]
    if not rules_texts and not weapon_texts:
        return {}
    b = base_rules(mod)
    out: dict = {}
    if rules_texts:
        names: set[str] = set()
        changed_tpl: set[str] = set()
        for text in rules_texts:
            for n in parse(text):
                key = n.key.lower()
                if key.startswith("^"):
                    changed_tpl.add(key)
                    continue
                if key in ("player", "world", "editorworld"):
                    continue
                names.add(key)
        merged = Rules(b["files"] + (b["campaign"] if campaign else []), rules_texts)


        if changed_tpl:
            for name in merged.names():
                if merged.inherits_from(name, changed_tpl):
                    names.add(name)
        if names:
            acts: dict[str, dict] = {}
            for name in sorted(names):
                r = merged.resolve(name)
                if r is None:
                    continue
                act = extract_actor(name, r, b["seqs"], b["fluent"])


                at = r.child("AutoTarget")
                if at is not None and at.get("InitialStanceAI", ""):
                    act["auto_target_ai"] = at.get("InitialStanceAI", "")
                if not act.get("sequences") and "." in name:
                    act["sequences"] = b["seqs"].get(name.split(".")[0], {})
                    act["image"] = name.split(".")[0]
                acts[name] = act
            if acts:
                out["actors"] = acts
    if weapon_texts:
        names_w: set[str] = set()
        for text in weapon_texts:
            for n in parse(text):
                if not n.key.startswith("^"):
                    names_w.add(n.key)
        merged_w = Rules(b["weapons"], weapon_texts)

        changed_templates = {n.key.lower() for text in weapon_texts for n in parse(text) if n.key.startswith("^")}
        for name in merged_w.names():
            raw = merged_w.raw.get(name)
            if raw is None:
                continue
            for c in raw.children:
                if (c.key == "Inherits" or c.key.startswith("Inherits@")) and c.value.lower() in changed_templates:
                    names_w.add(name)
        weaps: dict[str, dict] = {}
        for name in sorted(names_w):
            w = merged_w.resolve(name)
            if w is not None:
                weaps[name.lower()] = extract_weapon(name, w, _BASE["seqs"])
        if weaps:
            out["weapons"] = weaps
    return out


def map_notifications(extras: dict[str, str]) -> dict[str, str]:

    out: dict[str, str] = {}
    for fname, text in extras.items():
        if not fname.endswith("notifications.yaml"):
            continue
        for n in parse(text):
            for c in n.children:
                if c.key == "Notifications":
                    for e in c.children:
                        out[e.key] = e.value
    return out


def convert(entry: Path, out: Path, mod: Path | None = None) -> dict | None:
    yaml, binary, png, extras = read_map(entry)
    nodes = {n.key: n for n in parse(yaml)}
    if "MapSize" not in nodes:
        return None
    width, height = (int(v) for v in nodes["MapSize"].value.split(","))
    bounds = [int(v) for v in nodes["Bounds"].value.split(",")] if "Bounds" in nodes else [0, 0, width, height]
    tiles, resources = parse_bin(binary, width, height)
    players = []
    for p in nodes.get("Players", Node("")).children:
        d = p.as_dict()
        players.append({
            "name": d.get("Name", ""), "playable": d.get("Playable") == "True", "bot": d.get("Bot", ""),
            "faction": d.get("Faction", ""), "non_combatant": d.get("NonCombatant") == "True",
            "owns_world": d.get("OwnsWorld") == "True", "required": d.get("Required") == "True",
            "enemies": [e.strip() for e in d.get("Enemies", "").split(",") if e.strip()],
            "allies": [e.strip() for e in d.get("Allies", "").split(",") if e.strip()],
            "color": d.get("Color", ""),
        })
    actors = []
    spawns = []
    for act in nodes.get("Actors", Node("")).children:
        d = act.as_dict()
        loc = d.get("Location", "0,0")
        x, y = (int(v) for v in loc.split(","))

        entry_ = {"id": act.key, "type": act.value.lower(), "owner": d.get("Owner", "Neutral"), "x": x, "y": y}
        for extra in ("Facing", "SubCell", "Health", "TurretFacing"):
            if extra in d:
                entry_[extra.lower()] = d[extra]


        if d.get("ScriptTags"):
            entry_["tags"] = [t.strip() for t in d["ScriptTags"].split(",") if t.strip()]
        if entry_["type"] == "mpspawn":
            spawns.append([x, y])
        actors.append(entry_)
    slug = slug_for(entry.stem)
    data = {
        "slug": slug,
        "title": nodes.get("Title", Node("", "")).value,
        "author": nodes.get("Author", Node("", "")).value,
        "tileset": nodes.get("Tileset", Node("", "TEMPERAT")).value.lower(),
        "width": width, "height": height, "bounds": bounds,
        "categories": [c.strip() for c in nodes.get("Categories", Node("", "")).value.split(",") if c.strip()],
        "visibility": nodes.get("Visibility", Node("", "")).value,
        "players": players, "spawns": spawns, "actors": actors,
        "tiles": base64.b64encode(tiles).decode("ascii"),
        "resources": base64.b64encode(resources).decode("ascii"),
        "scripts": [n for n in extras if n.endswith(".lua")],
        "notifications": map_notifications(extras),
    }
    data.update(mission_rules(extras))
    if mod is not None:

        campaign = bool(data.get("mission_data")) or bool(data["scripts"])


        data["campaign"] = campaign
        override = map_rules_override(extras, mod, campaign)
        if override:
            data["rules_override"] = override


            data["rules_format"] = RULES_FORMAT
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{slug}.json").write_text(json.dumps(data, separators=(",", ":")))
    if png:
        (out / f"{slug}.png").write_bytes(png)
    for n, text in extras.items():
        (out / f"{slug}.{n}").write_text(text)
    return {"slug": slug, "title": data["title"], "tileset": data["tileset"], "players": len(spawns),
            "categories": data["categories"], "visibility": data["visibility"], "size": [bounds[2], bounds[3]],
            "preview": bool(png), "scripts": data["scripts"],
            "videos": data.get("mission_data", {}).get("videos", {})}


def read_campaigns(path: Path) -> list[dict]:

    if not path.exists():
        return []
    out: list[dict] = []
    for n in parse(path.read_text(encoding="utf-8")):
        slugs = []
        for c in n.children:
            stem = c.key.split("/")[-1]
            slugs.append(slug_for(Path(stem).stem))
        if slugs:
            out.append({"name": n.key, "maps": slugs})
    return out


def extra_map_dirs(extra: Path) -> list[Path]:

    if not extra.exists():
        return []
    return sorted(p for p in extra.iterdir() if p.is_dir() and (p / "map.yaml").exists())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("maps", nargs="*")
    ap.add_argument("-o", "--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--openra", type=Path, default=DEFAULT_OPENRA)
    ap.add_argument("--extra", type=Path, default=DEFAULT_EXTRA)
    a = ap.parse_args()
    maps_dir = a.openra / "mods" / "ra" / "maps"
    if a.maps:
        entries = [Path(m) if Path(m).exists() else
                   (maps_dir / m if (maps_dir / m).exists() else a.extra / m) for m in a.maps]
    else:
        ref_entries = sorted(maps_dir.iterdir())

        ref_slugs = {slug_for(e.stem) for e in ref_entries}
        entries = ref_entries + [e for e in extra_map_dirs(a.extra) if slug_for(e.stem) not in ref_slugs]
    index = []
    for e in entries:
        if not (e.is_dir() and (e / "map.yaml").exists()) and e.suffix != ".oramap":
            continue
        try:
            info = convert(e, a.out, a.openra / "mods" / "ra")
        except Exception as ex:
            print(f"  {e.name}: übersprungen ({ex})")
            continue
        if info:
            index.append(info)
    index.sort(key=lambda m: (m["categories"], m["title"]))


    campaigns = read_campaigns(a.extra / "campaigns.yaml") + read_campaigns(a.openra / "mods" / "ra" / "missions.yaml")
    if campaigns:
        (a.out / "campaigns.json").write_text(json.dumps(campaigns, indent=1, ensure_ascii=False))
        print(f"{len(campaigns)} Kampagnen → {a.out / 'campaigns.json'}")
    a.out.mkdir(parents=True, exist_ok=True)
    (a.out / "index.json").write_text(json.dumps(index, indent=1, ensure_ascii=False))
    print(f"{len(index)} Karten → {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

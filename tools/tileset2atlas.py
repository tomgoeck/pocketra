#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rafmt import ContentSet, NameDatabase, ShpFile, TmpFile, load_palette
from rafmt.miniyaml import Rules, parse_file
from rafmt.shp import looks_like_shp
from shp2atlas import _Frames, _pack

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONTENT = ROOT / "content" / "ra"
DEFAULT_OUT = ROOT / "game" / "assets" / "atlas"
DEFAULT_OPENRA = ROOT / "reference" / "OpenRA"
DB = Path(__file__).resolve().parent / "rafmt" / "global_mix_database.dat"

TILESET_EXT = {"temperat": "tem", "snow": "sno", "interior": "int", "desert": "des"}
PALETTES = {"temperat": "temperat.pal", "snow": "snow.pal", "interior": "interior.pal", "desert": "desert.pal"}


class Content:


    def __init__(self, content: Path, bits: Path):
        self.cs = ContentSet(content, NameDatabase(DB))
        self.bits = bits


    BITS_FIRST = {"scrate.shp", "wcrate.shp", "xcratea.shp", "xcrateb.shp", "xcratec.shp", "xcrated.shp"}

    def read(self, name: str) -> bytes | None:
        p = self.bits / name.lower()
        if name.lower() in self.BITS_FIRST and p.exists():
            return p.read_bytes()
        try:
            return self.cs.read(name)
        except Exception:
            pass
        if p.exists():
            return p.read_bytes()
        return None


def load_frames(raw: bytes, name: str) -> _Frames:
    if name.lower().endswith(".shp") or looks_like_shp(raw):
        s = ShpFile(raw)
        return _Frames(s.width, s.height, s.frames)
    t = TmpFile(raw)
    empty = bytes(t.width * t.height)
    return _Frames(t.width, t.height, [tile if tile is not None else empty for tile in t.tiles])


def map_actor_names(maps_dir: Path) -> set[str]:

    names: set[str] = set()
    pat = re.compile(r"^\t[A-Za-z0-9]+: ([a-z0-9.]+)$", re.M)
    for entry in maps_dir.iterdir():
        text = ""
        if entry.is_dir() and (entry / "map.yaml").exists():
            text = (entry / "map.yaml").read_text(encoding="utf-8", errors="replace")
        elif entry.suffix == ".oramap":
            with zipfile.ZipFile(entry) as z:
                text = z.read("map.yaml").decode("utf-8", errors="replace")
        else:
            continue
        in_actors = False
        for line in text.splitlines():
            if line.startswith("Actors:"):
                in_actors = True
                continue
            if in_actors and line and not line.startswith("\t"):
                in_actors = False
            if in_actors:
                m = pat.match(line)
                if m:
                    names.add(m.group(1))
    return names


def sequence_filename(seqs: dict[str, object], actor: str, tileset: str) -> str | None:

    node = seqs.get(actor)
    if node is None:
        return None
    for seq in ("idle", "Defaults"):
        n = node.child(seq)
        if n is None:
            continue
        tf = n.child("TilesetFilenames")
        if tf is not None:
            v = tf.get(tileset.upper())
            if v:
                return v
        fn = n.get("Filename")
        if fn:
            return fn
    d = node.child("Defaults")
    if d is not None:
        tf = d.child("TilesetFilenames")
        if tf is not None and tf.get(tileset.upper()):
            return tf.get(tileset.upper())
        if d.get("Filename"):
            return d.get("Filename")
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tileset")
    ap.add_argument("-o", "--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--content", type=Path, default=DEFAULT_CONTENT)
    ap.add_argument("--openra", type=Path, default=DEFAULT_OPENRA)
    a = ap.parse_args()

    tileset = a.tileset.lower()
    ext = TILESET_EXT[tileset]
    mod = a.openra / "mods" / "ra"
    content = Content(a.content, mod / "bits")
    ts = parse_file(mod / "tilesets" / f"{tileset}.yaml")
    terrain_node = next(n for n in ts if n.key == "Terrain")
    terrain_types = [c.get("Type") for c in terrain_node.children]


    terrain_colors = {c.get("Type"): c.get("Color", "000000") for c in terrain_node.children}
    templates_node = next(n for n in ts if n.key == "Templates")

    sprites: dict[str, _Frames] = {}
    templates: dict[int, dict] = {}
    missing: list[str] = []

    def add_sprite(stem: str, filename: str) -> bool:
        if stem in sprites:
            return True
        raw = content.read(filename)
        if raw is None:
            missing.append(filename)
            return False
        try:
            sprites[stem] = load_frames(raw, filename)
        except Exception as ex:
            missing.append(f"{filename} ({ex})")
            return False
        return True

    for t in templates_node.children:
        tid = int(t.get("Id"))
        image = t.get("Images").split(",")[0].strip()
        stem = Path(image).stem.lower()
        if not add_sprite(stem, image):
            continue
        w, h = (int(v) for v in t.get("Size").split(","))
        tiles = {}
        tn = t.child("Tiles")
        if tn is not None:
            for c in tn.children:
                tiles[int(c.key)] = terrain_types.index(c.value)
        templates[tid] = {"image": stem, "w": w, "h": h, "tiles": tiles, "pick_any": t.get("PickAny") == "True"}


    for stem in ["gold01", "gold02", "gold03", "gold04", "gem01", "gem02", "gem03", "gem04", "bib1", "bib2", "bib3"]:
        add_sprite(stem, f"{stem}.{ext}")


    rules = Rules(sorted((mod / "rules").glob("*.yaml")))
    seq_nodes: dict[str, object] = {}
    for f in (mod / "sequences").glob("*.yaml"):
        for n in parse_file(f):
            seq_nodes[n.key.lower()] = n
    decorations: dict[str, dict] = {}
    for name in sorted(map_actor_names(mod / "maps")):
        r = rules.resolve(name)
        if r is None or r.child("Building") is None:
            continue
        if r.child("Buildable") is not None and r.child("Wall") is None:
            continue
        b = r.child("Building")
        fn = sequence_filename(seq_nodes, name, tileset) or f"{name}.shp"
        stem = Path(fn).stem.lower()
        if not add_sprite(stem, fn):
            alt = f"{name}.{ext}" if not fn.endswith(f".{ext}") else f"{name}.shp"
            stem = Path(alt).stem.lower()
            if not add_sprite(stem, alt):
                continue
        hp = r.child("Health").get("HP") if r.child("Health") else "0"
        decorations[name] = {
            "sprite": stem,
            "footprint": b.get("Footprint", "x"),
            "dimensions": b.get("Dimensions", "1,1"),
            "hp": int(hp or 0),
            "wall": r.child("Wall") is not None,
            "targetable": r.child("Targetable") is not None and r.child("Health") is not None,
        }


    for line in (Path(__file__).resolve().parent / "unit_sprites.txt").read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        parts = line.split()
        if parts[0].startswith("@"):
            if parts[0][1:] != tileset:
                continue
            parts = parts[1:]
        for fn in parts:
            add_sprite(Path(fn).stem.lower(), fn)

    items = [(s.width, s.height) for s in sprites.values() for _ in s.frames]
    width, height, positions = _pack(items, max_width=4096)
    atlas = bytearray(width * height)
    frames = []
    k = 0
    for stem, s in sprites.items():
        for fi, frame in enumerate(s.frames):
            x, y = positions[k]
            k += 1
            for row in range(s.height):
                dst = (y + row) * width + x
                atlas[dst:dst + s.width] = frame[row * s.width:(row + 1) * s.width]
            frames.append({"sprite": stem, "frame": fi, "x": x, "y": y, "w": s.width, "h": s.height})

    a.out.mkdir(parents=True, exist_ok=True)
    name = f"atlas_{tileset}"
    (a.out / f"{name}.r8").write_bytes(atlas)
    (a.out / f"{name}.json").write_text(json.dumps({
        "width": width, "height": height, "frames": frames,
        "terrain_types": terrain_types,
        "terrain_colors": terrain_colors,


        "default_terrain": terrain_types.index("Clear") if "Clear" in terrain_types else 0,
        "templates": {str(k): v for k, v in templates.items()},
        "decorations": decorations,
    }, separators=(",", ":")))
    pal_name = PALETTES[tileset]
    pal = load_palette(content.read(pal_name))
    rgba = bytearray()
    for i, (r, g, b) in enumerate(pal):
        rgba += bytes((r, g, b, 0 if i == 0 else 255))
    (a.out / f"{tileset}.rgba").write_bytes(rgba)
    print(f"{name}: {len(frames)} Frames aus {len(sprites)} Sprites → {width}×{height} ({len(atlas) // 1024} KB), "
          f"{len(templates)} Templates, {len(decorations)} Dekorationen; fehlend: {len(missing)} ({', '.join(missing[:8])})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

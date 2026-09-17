#!/usr/bin/env python3

import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rafmt import ContentSet, NameDatabase, ShpFile, load_palette
from shp2atlas import _Frames, _pack

ROOT = Path(__file__).resolve().parent.parent
DB = Path(__file__).resolve().parent / "rafmt" / "global_mix_database.dat"


def icon_names(cs: ContentSet) -> list[str]:
    names = {e.name for m in cs.mixes for e in m.entries
             if e.name and e.name.lower().endswith("icon.shp")}
    return sorted(names)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--content", type=Path, default=ROOT / "content" / "ra")
    ap.add_argument("--content-de", type=Path, default=ROOT / "content" / "ra_de")
    ap.add_argument("-o", "--out", type=Path, default=ROOT / "game" / "assets" / "atlas")
    ap.add_argument("--recipe", type=Path, default=ROOT / "game" / "data" / "atlas")
    ap.add_argument("--name", default="cameos_de")
    ap.add_argument("--extra", type=Path, default=ROOT / "build" / "cameos_de",
                    help="Ordner mit zusätzlichen *.shp (tools/cameo_de_labels.py), die mit in den "
                         "Atlas gehen — fehlt er, wird er stillschweigend übersprungen")
    a = ap.parse_args()

    if not a.content_de.is_dir():
        print(f"keine deutsche CD unter {a.content_de} — nichts zu tun", file=sys.stderr)
        return 0
    names = NameDatabase(DB)
    de = ContentSet(a.content_de, names)
    en = ContentSet(a.content, names) if a.content.is_dir() else None


    take: list[str] = []
    for n in icon_names(de):
        if en is not None:
            try:
                if hashlib.md5(en.read(n)).digest() == hashlib.md5(de.read(n)).digest():
                    continue
            except KeyError:
                pass
        take.append(n)
    if not take:
        print("keine abweichenden Cameos gefunden", file=sys.stderr)
        return 1

    sprites = [(Path(n).stem.lower(), n, ShpFile(de.read(n))) for n in take]


    extra: list[str] = []
    if a.extra.is_dir():
        have = {s for s, _, _ in sprites}
        for p in sorted(a.extra.glob("*.shp")):
            stem = p.stem.lower()
            if stem in have:
                continue
            sprites.append((stem, p.name, ShpFile(p.read_bytes())))
            extra.append(stem)
    frames_in = [_Frames(s.width, s.height, s.frames) for _, _, s in sprites]
    items = [(f.width, f.height) for f in frames_in for _ in f.frames]
    width, height, positions = _pack(items)

    atlas = bytearray(width * height)
    frames = []
    k = 0
    for (stem, _fn, _shp), f in zip(sprites, frames_in):
        for fi, frame in enumerate(f.frames):
            x, y = positions[k]
            k += 1
            for row in range(f.height):
                dst = (y + row) * width + x
                atlas[dst:dst + f.width] = frame[row * f.width:(row + 1) * f.width]
            frames.append({"sprite": stem, "frame": fi, "x": x, "y": y, "w": f.width, "h": f.height})

    a.out.mkdir(parents=True, exist_ok=True)
    (a.out / f"atlas_{a.name}.r8").write_bytes(atlas)
    (a.out / f"atlas_{a.name}.json").write_text(json.dumps(
        {"width": width, "height": height, "frames": frames}, separators=(",", ":")))

    if not (a.out / "temperat.rgba").exists():
        pal = load_palette(de.read("temperat.pal"))
        rgba = bytearray()
        for i, (r, g, b) in enumerate(pal):
            rgba += bytes((r, g, b, 0 if i == 0 else 255))
        (a.out / "temperat.rgba").write_bytes(rgba)

    a.recipe.mkdir(parents=True, exist_ok=True)
    lines = ["format 1", f"tileset {a.name}", "palette temperat.pal", "max_width 2048", "bits_first "]
    lines += [f"sprite {stem} {fn}" for stem, fn, _ in sprites if stem not in extra]
    lines.append("meta ")
    (a.recipe / f"{a.name}.recipe").write_text("\n".join(lines) + "\n")

    print(f"atlas_{a.name}: {len(frames)} Frames aus {len(sprites)} Cameos → {width}×{height} "
          f"({len(atlas) // 1024} KB); Rezept in {a.recipe}")
    print("abweichend: " + " ".join(stem for stem, _, _ in sprites if stem not in extra))
    if extra:
        print(f"nachgebaut ({a.extra}): " + " ".join(extra))
    return 0


if __name__ == "__main__":
    sys.exit(main())

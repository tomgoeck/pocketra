#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_volkicon import RESERVED, encode_shp
from rafmt import ContentSet, NameDatabase, load_palette

ROOT = Path(__file__).resolve().parent.parent
DB = Path(__file__).resolve().parent / "rafmt" / "global_mix_database.dat"
W, H = 64, 48


def trim_border(im):

    px = im.load()
    w, h = im.size

    def edge_is_border(coords) -> bool:
        vals = [px[x, y] for x, y in coords]
        flat = sum(1 for r, g, b in vals if (r > 235 and g > 235 and b > 235) or (r < 12 and g < 12 and b < 12))
        return flat >= 0.9 * len(vals)

    l, t, r, b = 0, 0, w, h
    while l < r - 1 and edge_is_border([(l, y) for y in range(t, b)]):
        l += 1
    while r - 1 > l and edge_is_border([(r - 1, y) for y in range(t, b)]):
        r -= 1
    while t < b - 1 and edge_is_border([(x, t) for x in range(l, r)]):
        t += 1
    while b - 1 > t and edge_is_border([(x, b - 1) for x in range(l, r)]):
        b -= 1
    return im.crop((l, t, r, b))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("png", type=Path)
    ap.add_argument("name", help="Zielname, z. B. volkicon.shp")
    ap.add_argument("--content", type=Path, default=ROOT / "content" / "ra")
    ap.add_argument("--palette", default="temperat.pal")
    ap.add_argument("--preview", action="store_true")
    a = ap.parse_args()
    from PIL import Image

    cs = ContentSet(a.content, NameDatabase(DB))
    pal = load_palette(cs.read(a.palette))
    allowed = sorted(set(range(256)) - RESERVED)
    im = trim_border(Image.open(a.png).convert("RGB"))
    im = im.resize((W, H), Image.LANCZOS)
    cache: dict[tuple[int, int, int], int] = {}
    idx = bytearray(W * H)
    for y in range(H):
        for x in range(W):
            rgb = im.getpixel((x, y))
            if rgb not in cache:
                cache[rgb] = min(allowed, key=lambda i: sum((pal[i][k] - rgb[k]) ** 2 for k in range(3)))
            idx[y * W + x] = cache[rgb]
    shp = encode_shp(W, H, bytes(idx))
    outs = [ROOT / "reference" / "OpenRA" / "mods" / "ra" / "bits" / a.name, ROOT / "game" / "data" / "bits" / a.name]
    for o in outs:
        if o.parent.exists():
            o.write_bytes(shp)
            print(f"{o} ({len(shp)} Bytes, {len(cache)} Farben → {len(set(idx))} Indizes)")
    if a.preview:
        pv = Image.new("RGB", (W, H))
        for y in range(H):
            for x in range(W):
                pv.putpixel((x, y), tuple(pal[idx[y * W + x]][:3]))
        p = a.png.with_name(a.png.stem + "_cameo_x8.png")
        pv.resize((W * 8, H * 8), Image.NEAREST).save(p)
        print(p)
    return 0


if __name__ == "__main__":
    sys.exit(main())

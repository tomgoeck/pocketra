#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rafmt import ContentSet, NameDatabase, ShpFile, load_palette

DB = Path(__file__).resolve().parent / "rafmt" / "global_mix_database.dat"
ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONTENT = ROOT / "content" / "ra"
BITS = ROOT / "reference" / "OpenRA" / "mods" / "ra" / "bits"


def read_shp(content: ContentSet, name: str) -> bytes:
    try:
        return content.read(name)
    except Exception:
        p = BITS / name
        if p.exists():
            return p.read_bytes()
        raise


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name")
    ap.add_argument("--palette", default="temperat.pal")
    ap.add_argument("--start", type=int, default=0, help="erster Frame")
    ap.add_argument("--frames", type=int, default=0, help="0 = alle ab --start")
    ap.add_argument("--crop", type=int, default=0, help="Rand je Seite abschneiden")
    ap.add_argument("--content", type=Path, default=DEFAULT_CONTENT)
    ap.add_argument("-o", "--out", type=Path, required=True)
    a = ap.parse_args()

    try:
        from PIL import Image
    except ImportError:
        print("Pillow fehlt: python3 -m pip install pillow", file=sys.stderr)
        return 2

    content = ContentSet(a.content, NameDatabase(DB))
    pal = load_palette(content.read(a.palette))
    shp = ShpFile(read_shp(content, a.name))
    first = max(0, a.start)
    n = (len(shp.frames) - first) if a.frames <= 0 else min(a.frames, len(shp.frames) - first)
    w, h = shp.width - 2 * a.crop, shp.height - 2 * a.crop
    sheet = Image.new("RGBA", (w * n, h))
    for k in range(n):
        i = first + k
        img = Image.frombytes("P", (shp.width, shp.height), bytes(shp.frames[i]))
        img.putpalette([c for rgb in pal for c in rgb[:3]])
        rgba = img.convert("RGBA")
        px = rgba.load()
        src = shp.frames[i]
        for y in range(shp.height):
            for x in range(shp.width):
                if src[y * shp.width + x] == 0:
                    px[x, y] = (0, 0, 0, 0)
        if a.crop:
            rgba = rgba.crop((a.crop, a.crop, shp.width - a.crop, shp.height - a.crop))
        sheet.paste(rgba, (k * w, 0))
    a.out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(a.out)
    print(f"{a.name}: {n} Frames à {w}×{h} → {a.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

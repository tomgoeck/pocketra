#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rafmt import ContentSet, NameDatabase, ShpFile, load_palette

DB = Path(__file__).resolve().parent / "rafmt" / "global_mix_database.dat"
DEFAULT_CONTENT = Path(__file__).resolve().parent.parent / "content" / "ra"
SHPS = {"allies": "natoradr.shp", "soviet": "ussrradr.shp"}
BORDER = 12


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--frames", type=int, default=21)
    ap.add_argument("--palette", default="temperat.pal")
    ap.add_argument("--content", type=Path, default=DEFAULT_CONTENT)
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parent.parent / "game" / "assets" / "ui")
    a = ap.parse_args()

    try:
        from PIL import Image
    except ImportError:
        print("Pillow fehlt: python3 -m pip install pillow", file=sys.stderr)
        return 2

    content = ContentSet(a.content, NameDatabase(DB))
    pal = load_palette(content.read(a.palette))
    a.out.mkdir(parents=True, exist_ok=True)
    for faction, shp_name in SHPS.items():
        shp = ShpFile(content.read(shp_name))
        n = min(a.frames, len(shp.frames))
        w, h = shp.width - 2 * BORDER, shp.height - 2 * BORDER
        sheet = Image.new("RGBA", (w * n, h))
        for i in range(n):
            idx = shp.frames[i]
            img = Image.frombytes("P", (shp.width, shp.height), bytes(idx))
            img.putpalette([c for rgb in pal for c in rgb[:3]])
            rgba = img.convert("RGBA").crop((BORDER, BORDER, shp.width - BORDER, shp.height - BORDER))
            sheet.paste(rgba, (i * w, 0))
        path = a.out / f"radar_{faction}.png"
        sheet.save(path)
        print(f"{shp_name}: {n} Frames à {w}×{h} → {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

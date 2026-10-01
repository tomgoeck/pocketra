#!/usr/bin/env python3


import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rafmt import ContentSet, NameDatabase, ShpFile, TmpFile, load_palette, write_indexed_png
from rafmt.png import compose_sheet

DB = Path(__file__).resolve().parent / "rafmt" / "global_mix_database.dat"
DEFAULT_CONTENT = Path(__file__).resolve().parent.parent / "content" / "ra"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name")
    ap.add_argument("--palette", default="temperat.pal")
    ap.add_argument("--cols", type=int)
    ap.add_argument("--gap", type=int, default=1)
    ap.add_argument("-o", "--out", type=Path)
    ap.add_argument("--content", type=Path, default=DEFAULT_CONTENT)
    a = ap.parse_args()

    cs = ContentSet(a.content, NameDatabase(DB))
    raw = cs.read(a.name)
    pal = load_palette(cs.read(a.palette))

    if a.name.lower().endswith(".shp"):
        f = ShpFile(raw); frames = f.frames
    else:
        f = TmpFile(raw); frames = [t or bytes(f.width * f.height) for t in f.tiles]

    cols = a.cols or max(1, math.ceil(math.sqrt(len(frames))))
    w, h, px = compose_sheet(frames, f.width, f.height, cols, gap=a.gap)
    out = a.out or Path(Path(a.name).stem + ".png")
    write_indexed_png(out, w, h, px, pal)
    print(f"{a.name}: {len(frames)} Frames à {f.width}×{f.height} → {out} ({w}×{h}, {cols} Spalten)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

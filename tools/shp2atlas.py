#!/usr/bin/env python3


import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rafmt import ContentSet, NameDatabase, ShpFile, TmpFile, load_palette
from rafmt.shp import looks_like_shp

DB = Path(__file__).resolve().parent / "rafmt" / "global_mix_database.dat"
DEFAULT_CONTENT = Path(__file__).resolve().parent.parent / "content" / "ra"
DEFAULT_OUT = Path(__file__).resolve().parent.parent / "game" / "assets" / "atlas"


def _pack(items: list[tuple[int, int]], max_width: int = 2048) -> tuple[int, int, list[tuple[int, int]]]:

    order = sorted(range(len(items)), key=lambda i: (-items[i][1], -items[i][0]))
    pos: list[tuple[int, int] | None] = [None] * len(items)
    x = y = shelf_h = 0
    width = 0
    for i in order:
        w, h = items[i]
        if x + w > max_width:
            y += shelf_h
            x = shelf_h = 0
        pos[i] = (x, y)
        x += w
        shelf_h = max(shelf_h, h)
        width = max(width, x)
    return width, y + shelf_h, pos


class _Frames:


    def __init__(self, width: int, height: int, frames: list[bytes]):
        self.width, self.height, self.frames = width, height, frames


def _load(cs: ContentSet, name: str) -> _Frames:
    raw = cs.read(name)
    if name.lower().endswith(".shp") or looks_like_shp(raw):
        s = ShpFile(raw)
        return _Frames(s.width, s.height, s.frames)
    t = TmpFile(raw)
    empty = bytes(t.width * t.height)
    return _Frames(t.width, t.height, [tile if tile is not None else empty for tile in t.tiles])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("atlas")
    ap.add_argument("names", nargs="+")
    ap.add_argument("-o", "--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--palette", default="temperat.pal")
    ap.add_argument("--content", type=Path, default=DEFAULT_CONTENT)
    a = ap.parse_args()

    cs = ContentSet(a.content, NameDatabase(DB))
    a.out.mkdir(parents=True, exist_ok=True)

    sprites: list[tuple[str, _Frames]] = [(Path(n).stem.lower(), _load(cs, n)) for n in a.names]
    items = [(s.width, s.height) for _, s in sprites for _ in s.frames]
    width, height, positions = _pack(items)

    atlas = bytearray(width * height)
    frames = []
    k = 0
    for name, s in sprites:
        for fi, frame in enumerate(s.frames):
            x, y = positions[k]
            k += 1
            for row in range(s.height):
                dst = (y + row) * width + x
                atlas[dst:dst + s.width] = frame[row * s.width:(row + 1) * s.width]
            frames.append({"sprite": name, "frame": fi, "x": x, "y": y, "w": s.width, "h": s.height})

    (a.out / f"{a.atlas}.r8").write_bytes(atlas)
    (a.out / f"{a.atlas}.json").write_text(json.dumps(
        {"width": width, "height": height, "frames": frames}, indent=1))

    pal = load_palette(cs.read(a.palette))
    rgba = bytearray()
    for i, (r, g, b) in enumerate(pal):
        rgba += bytes((r, g, b, 0 if i == 0 else 255))
    (a.out / (Path(a.palette).stem + ".rgba")).write_bytes(rgba)

    print(f"{a.atlas}: {len(frames)} Frames aus {len(sprites)} Sprites → {width}×{height} "
          f"({len(atlas) // 1024} KB), Palette {a.palette}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

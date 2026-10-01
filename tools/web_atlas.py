#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

PAGE = 2048


MAX_PAGES = 6

DEFAULT_DIR = Path(__file__).resolve().parents[1] / "game/assets/atlas"


def pack(frames):

    shelves = []
    placed = [None] * len(frames)
    for index, frame in sorted(enumerate(frames), key=lambda item: (-item[1]["h"], -item[1]["w"])):
        for page, rows in enumerate(shelves):
            for row in rows:
                if frame["h"] <= row["height"] and row["x"] + frame["w"] <= PAGE:
                    placed[index] = (page, row["x"], row["y"])
                    row["x"] += frame["w"]
                    break
            if placed[index] is not None:
                break
            next_y = sum(row["height"] for row in rows)
            if next_y + frame["h"] <= PAGE:
                rows.append({"height": frame["h"], "x": frame["w"], "y": next_y})
                placed[index] = (page, 0, next_y)
                break
        if placed[index] is None:
            shelves.append([{"height": frame["h"], "x": frame["w"], "y": 0}])
            placed[index] = (len(shelves) - 1, 0, 0)
    return placed, len(shelves)


def needs_pages(meta) -> bool:

    return meta["width"] > PAGE or meta["height"] > PAGE


def page_path(web_base: Path, page: int) -> Path:
    return web_base.with_name("%s_%d.r8" % (web_base.name, page))


def clear_pages(web_base: Path) -> int:

    removed = 0
    for path in sorted(web_base.parent.glob(web_base.name + "_*.r8")):
        path.unlink()
        removed += 1
    meta_path = web_base.with_suffix(".json")
    if meta_path.exists():
        meta_path.unlink()
    return removed


def build(atlas_base: Path, force: bool = False, quiet: bool = False) -> int:

    meta = json.loads(atlas_base.with_suffix(".json").read_text())
    web_base = atlas_base.with_name(atlas_base.name + "_web")
    if not force and not needs_pages(meta):


        removed = clear_pages(web_base)
        if not quiet:
            note = " (%d alte Seite(n) entfernt)" % removed if removed else ""
            print("%s: %d×%d passt in eine WebGL-Seite, übersprungen%s"
                  % (atlas_base.name, meta["width"], meta["height"], note))
        return 0

    raw = atlas_base.with_suffix(".r8").read_bytes()
    width, height = meta["width"], meta["height"]
    if len(raw) != width * height:
        raise SystemExit("%s.r8 hat %d Bytes, die Metadaten sagen %d×%d"
                         % (atlas_base, len(raw), width, height))
    positions, page_count = pack(meta["frames"])
    if page_count > MAX_PAGES:
        raise SystemExit("%s braucht %d Seiten, der Shader hat %d Sampler — MAX_PAGES in "
                         "tools/web_atlas.py und game/scripts/palette_atlas.gd erhöhen und "
                         "game/shaders/palette_sprite.gdshader um weitere atlasN erweitern"
                         % (atlas_base.name, page_count, MAX_PAGES))

    too_big = sorted({f["sprite"] for f in meta["frames"] if f["w"] > 255 or f["h"] > 255})
    if too_big:
        raise SystemExit("%s: Frames über 255 Pixel passen nicht in die Frametabelle: %s"
                         % (atlas_base.name, too_big[:5]))

    pages = [bytearray(PAGE * PAGE) for _ in range(page_count)]
    for frame, (page, dx, dy) in zip(meta["frames"], positions):
        for row in range(frame["h"]):
            src = (frame["y"] + row) * width + frame["x"]
            dst = (dy + row) * PAGE + dx
            pages[page][dst:dst + frame["w"]] = raw[src:src + frame["w"]]
        frame["x"], frame["y"], frame["page"] = dx, dy, page
    meta["width"] = PAGE
    meta["height"] = PAGE
    meta["pages"] = page_count

    clear_pages(web_base)
    web_base.with_suffix(".json").write_text(json.dumps(meta, separators=(",", ":")))
    for page, data in enumerate(pages):
        page_path(web_base, page).write_bytes(data)
    if not quiet:
        used = sum(f["w"] * f["h"] for f in meta["frames"])
        print("%s: %d Frames → %d WebGL-Seiten (%d %% gefüllt)"
              % (atlas_base.name, len(meta["frames"]), page_count,
                 round(100.0 * used / (page_count * PAGE * PAGE))))
    return page_count


def resolve(token: str, directory: Path) -> Path:

    candidate = Path(token)
    if candidate.suffix in (".json", ".r8"):
        candidate = candidate.with_suffix("")
    if candidate.with_suffix(".json").exists():
        return candidate
    for name in (candidate.name, "atlas_%s" % candidate.name):
        base = directory / name
        if base.with_suffix(".json").exists():
            return base
    raise SystemExit("kein Atlas zu %r gefunden (gesucht in %s)" % (token, directory))


def discover(directory: Path):

    out = []
    for meta_path in sorted(directory.glob("*.json")):
        base = meta_path.with_suffix("")
        if base.name.endswith("_web") or "_web_" in base.name:
            continue
        if base.with_suffix(".r8").exists():
            out.append(base)
    return out


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("atlas", nargs="*", help="Basispfad, .json-Pfad oder bloßer Name")
    parser.add_argument("--dir", type=Path, default=DEFAULT_DIR,
                        help="Suchordner (Standard: %s)" % DEFAULT_DIR)
    parser.add_argument("--all", action="store_true",
                        help="auch Atlanten packen, die schon in eine Seite passen")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)

    if args.atlas:
        bases = [resolve(token, args.dir) for token in args.atlas]
    else:
        bases = discover(args.dir)
        if not bases:
            raise SystemExit("keine Atlanten in %s — erst tools/tileset2atlas.py laufen lassen" % args.dir)
    for base in bases:
        build(base, force=args.all, quiet=args.quiet)
    return 0


if __name__ == "__main__":
    sys.exit(main())

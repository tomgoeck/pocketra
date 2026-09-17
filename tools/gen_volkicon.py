#!/usr/bin/env python3

from __future__ import annotations

import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rafmt import ContentSet, NameDatabase, ShpFile, load_palette

ROOT = Path(__file__).resolve().parent.parent
DB = Path(__file__).resolve().parent / "rafmt" / "global_mix_database.dat"
DEFAULT_CONTENT = ROOT / "content" / "ra"
DEFAULT_OUT = ROOT / "reference" / "OpenRA" / "mods" / "ra" / "bits" / "volkicon.shp"

W, H = 64, 48


RESERVED = {0, 4} | set(range(80, 96))


def encode_shp(width: int, height: int, indices: bytes) -> bytes:


    body = bytearray()
    for i in range(0, len(indices), 63):
        chunk = indices[i:i + 63]
        body.append(0x80 | len(chunk))
        body += chunk
    body.append(0x80)

    header_size = 14 + 8 * (1 + 2)
    data_offset = header_size
    file_len = data_offset + len(body)

    out = bytearray()
    out += struct.pack("<H", 1)
    out += b"\x00" * 4
    out += struct.pack("<HH", width, height)
    out += b"\x00" * 4

    out += struct.pack("<I", (data_offset & 0xFFFFFF) | (0x80 << 24))
    out += struct.pack("<HH", 0, 0)

    out += struct.pack("<I", file_len & 0xFFFFFF)
    out += struct.pack("<HH", 0, 0)
    out += struct.pack("<I", 0)
    out += struct.pack("<HH", 0, 0)
    out += body
    assert len(out) == file_len
    return bytes(out)


def nearest_index(rgb: tuple[int, int, int], pal: list[tuple[int, int, int]], allowed: set[int]) -> int:
    best, best_d = 0, None
    for i in allowed:
        pr, pg, pb = pal[i]
        d = (pr - rgb[0]) ** 2 + (pg - rgb[1]) ** 2 + (pb - rgb[2]) ** 2
        if best_d is None or d < best_d:
            best, best_d = i, d
    return best


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--content", type=Path, default=DEFAULT_CONTENT)
    ap.add_argument("-o", "--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--plate", type=Path, default=None,
                    help="zusätzlich die reine Hintergrundplatte (64×48 Indizes, ohne die Figur aus "
                         "gnrl.shp) schreiben — sie ist Eigenarbeit und darf in die APK, damit "
                         "RaContent das Cameo auf dem Gerät zusammensetzt")
    a = ap.parse_args()

    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("Pillow fehlt: python3 -m pip install pillow", file=sys.stderr)
        return 2

    cs = ContentSet(a.content, NameDatabase(DB))
    shp = ShpFile(cs.read("gnrl.shp"))
    pal = load_palette(cs.read("temperat.pal"))
    sw, sh = shp.width, shp.height
    src = shp.frames[0]


    crop = (19, 3, 30, 21)
    cw, ch = crop[2] - crop[0], crop[3] - crop[1]
    scale = 2
    char_w, char_h = cw * scale, ch * scale
    ox = (W - char_w) // 2
    oy = 1


    canvas = Image.new("RGB", (W, H), (30, 6, 6))
    d = ImageDraw.Draw(canvas)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W - 1, y)], fill=(int(30 + 18 * t), int(6 + 3 * t), int(6 + 3 * t)))
    d.rectangle([0, 0, W - 1, H - 1], outline=(196, 150, 60))
    font = ImageFont.load_default()
    text = "VOLKOV"
    bbox = d.textbbox((0, 0), text, font=font)
    tx = (W - (bbox[2] - bbox[0])) // 2 - bbox[0]
    ty = H - 10
    for dxo, dyo in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        d.text((tx + dxo, ty + dyo), text, font=font, fill=(0, 0, 0))
    d.text((tx, ty), text, font=font, fill=(255, 222, 140))


    allowed = set(range(256)) - RESERVED
    color_cache: dict[tuple[int, int, int], int] = {}
    out_indices = bytearray(W * H)
    plate = bytearray(W * H)
    for y in range(H):
        for x in range(W):
            rgb0 = canvas.getpixel((x, y))
            if rgb0 not in color_cache:
                color_cache[rgb0] = nearest_index(rgb0, pal, allowed)
            plate[y * W + x] = color_cache[rgb0]


            if ox <= x < ox + char_w and oy <= y < oy + char_h:
                sx = crop[0] + (x - ox) // scale
                sy = crop[1] + (y - oy) // scale
                si = src[sy * sw + sx]
                if si not in (0, 4):
                    out_indices[y * W + x] = si
                    continue
            rgb = canvas.getpixel((x, y))
            if rgb not in color_cache:
                color_cache[rgb] = nearest_index(rgb, pal, allowed)
            out_indices[y * W + x] = color_cache[rgb]

    if a.plate is not None:
        a.plate.parent.mkdir(parents=True, exist_ok=True)
        a.plate.write_bytes(bytes(plate))
        print(f"{a.plate} ({W}x{H} Indizes, nur Hintergrund)")

    shp_bytes = encode_shp(W, H, bytes(out_indices))

    check = ShpFile(shp_bytes)
    assert len(check.frames) == 1 and check.frames[0] == bytes(out_indices), "SHP-Rundreise fehlgeschlagen"

    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_bytes(shp_bytes)
    print(f"{a.out} ({len(shp_bytes)} Bytes, {W}x{H})")
    return 0


if __name__ == "__main__":
    sys.exit(main())



import struct
import zlib


def _chunk(tag: bytes, body: bytes) -> bytes:
    return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)


def write_indexed_png(path, width: int, height: int, pixels: bytes,
                      palette: list[tuple[int, int, int]], transparent_index: int | None = 0) -> None:
    if len(pixels) != width * height:
        raise ValueError(f"Pixeldaten {len(pixels)} ≠ {width}×{height}")
    rows = b"".join(b"\0" + pixels[y * width:(y + 1) * width] for y in range(height))
    plte = b"".join(bytes(c) for c in palette[:256])
    out = [
        b"\x89PNG\r\n\x1a\n",
        _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0)),
        _chunk(b"PLTE", plte),
    ]
    if transparent_index is not None:
        out.append(_chunk(b"tRNS", b"\xff" * transparent_index + b"\x00"))
    out.append(_chunk(b"IDAT", zlib.compress(rows, 9)))
    out.append(_chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(b"".join(out))


def compose_sheet(frames: list[bytes], width: int, height: int,
                  cols: int, gap: int = 0, fill: int = 0) -> tuple[int, int, bytes]:

    n = len(frames)
    rows = (n + cols - 1) // cols
    sw = cols * width + (cols - 1) * gap
    sh = rows * height + (rows - 1) * gap
    sheet = bytearray(bytes((fill,)) * (sw * sh))
    for i, frame in enumerate(frames):
        cx = (i % cols) * (width + gap)
        cy = (i // cols) * (height + gap)
        for y in range(height):
            dst = (cy + y) * sw + cx
            sheet[dst:dst + width] = frame[y * width:(y + 1) * width]
    return sw, sh, bytes(sheet)

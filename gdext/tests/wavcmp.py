#!/usr/bin/env python3

import struct
import sys
from pathlib import Path


def data_chunk(path: Path) -> tuple[bytes, tuple]:
    raw = path.read_bytes()
    assert raw[:4] == b"RIFF" and raw[8:12] == b"WAVE", f"{path}: kein WAV"
    pos = 12
    fmt = ()
    while pos + 8 <= len(raw):
        cid = raw[pos:pos + 4]
        size = struct.unpack_from("<I", raw, pos + 4)[0]
        body = raw[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            fmt = struct.unpack_from("<HHIIHH", body, 0)
        if cid == b"data":
            return body, fmt
        pos += 8 + size + (size & 1)
    return b"", fmt


def main() -> int:
    a, b = Path(sys.argv[1]), Path(sys.argv[2])
    name = sys.argv[3] if len(sys.argv) > 3 else str(a)
    if not b.exists():
        print(f"  {name}: Vergleichsdatei fehlt", file=sys.stderr)
        return 1
    da, fa = data_chunk(a)
    db, fb = data_chunk(b)
    if fa[:4] != fb[:4] or fa[5] != fb[5]:
        print(f"  {name}: Format {fa} != {fb}", file=sys.stderr)
        return 1
    if da != db:
        n = min(len(da), len(db))
        first = next((i for i in range(n) if da[i] != db[i]), n)
        print(f"  {name}: {len(da)} vs {len(db)} Bytes, erste Abweichung bei {first}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

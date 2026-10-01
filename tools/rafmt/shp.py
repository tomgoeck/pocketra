

import struct
from dataclasses import dataclass

from .lcw import lcw_decode, xor_delta_decode

LCW, XOR_REF, XOR_PREV = 0x80, 0x40, 0x20


@dataclass
class _Header:
    offset: int
    fmt: int
    ref_offset: int
    ref_fmt: int
    data: bytearray | None = None


def looks_like_shp(raw: bytes) -> bool:

    if len(raw) < 20:
        return False
    (count,) = struct.unpack_from("<H", raw, 0)
    if count == 0:
        return False
    eof_pos = 14 + 8 * count
    if eof_pos + 4 > len(raw):
        return False
    (eof,) = struct.unpack_from("<I", raw, eof_pos)
    return eof == len(raw) and raw[17] in (0x20, 0x40, 0x80)


class ShpFile:
    def __init__(self, raw: bytes):
        (count,) = struct.unpack_from("<H", raw, 0)
        self.width, self.height = struct.unpack_from("<HH", raw, 6)
        headers: list[_Header] = []
        pos = 14
        for _ in range(count):
            (packed, ref_off, ref_fmt) = struct.unpack_from("<IHH", raw, pos)
            pos += 8
            headers.append(_Header(packed & 0xFFFFFF, packed >> 24, ref_off, ref_fmt))

        by_offset = {h.offset: h for h in headers}
        size = self.width * self.height
        self.frames: list[bytes] = []

        def decode(i: int, depth: int = 0) -> bytearray:
            h = headers[i]
            if h.data is not None:
                return h.data
            if depth > count:
                raise ValueError("SHP: zyklische Frame-Referenz")
            if h.fmt == LCW:
                buf = bytearray(size)
                lcw_decode(raw, h.offset, buf)
            elif h.fmt == XOR_PREV:
                buf = bytearray(decode(i - 1, depth + 1))
                xor_delta_decode(raw, h.offset, buf)
            elif h.fmt == XOR_REF:
                ref = by_offset.get(h.ref_offset)
                if ref is None:
                    raise ValueError(f"SHP: Referenz {h.ref_offset:#x} zeigt auf keinen Frame")
                buf = bytearray(decode(headers.index(ref), depth + 1))
                xor_delta_decode(raw, h.offset, buf)
            else:
                raise ValueError(f"SHP: unbekanntes Frameformat {h.fmt:#x}")
            h.data = buf
            return buf

        for i in range(count):
            self.frames.append(bytes(decode(i)))

    def __len__(self) -> int:
        return len(self.frames)

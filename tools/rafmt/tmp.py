

import struct


class TmpFile:
    def __init__(self, raw: bytes):
        self.width, self.height = struct.unpack_from("<HH", raw, 0)
        (img_start,) = struct.unpack_from("<I", raw, 16)
        (index_end,) = struct.unpack_from("<i", raw, 28)
        (index_start,) = struct.unpack_from("<i", raw, 36)
        size = self.width * self.height
        self.tiles: list[bytes | None] = []
        for b in raw[index_start:index_end]:
            if b == 255:
                self.tiles.append(None)
            else:
                off = img_start + b * size
                self.tiles.append(raw[off:off + size])

    def __len__(self) -> int:
        return len(self.tiles)

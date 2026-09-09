

import struct
from pathlib import Path


def classic_hash(name: str) -> int:

    data = name.upper().encode("ascii")
    pad = (-len(data)) % 4
    data += b"\0" * pad
    result = 0
    for (word,) in struct.iter_unpack("<I", data):
        result = (((result << 1) | (result >> 31)) + word) & 0xFFFFFFFF
    return result


class NameDatabase:


    def __init__(self, path: Path):
        data = Path(path).read_bytes()
        names: list[str] = []
        pos = 0
        n = len(data)
        while pos + 4 <= n:
            (count,) = struct.unpack_from("<i", data, pos)
            pos += 4
            for _ in range(count):
                end = data.index(b"\0", pos)
                names.append(data[pos:end].decode("latin-1"))
                pos = end + 1
                pos = data.index(b"\0", pos) + 1
        self.names = names
        self._by_hash: dict[int, str] = {}
        for name in names:
            self._by_hash.setdefault(classic_hash(name), name)

    def lookup(self, hash_value: int) -> str | None:
        return self._by_hash.get(hash_value)

    def __len__(self) -> int:
        return len(self.names)

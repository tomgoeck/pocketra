

import struct
import sys
from dataclasses import dataclass
from pathlib import Path

from .blowfish import Blowfish
from .mixkey import decrypt_blowfish_key
from .names import NameDatabase, classic_hash

_ENTRY = struct.Struct("<III")


@dataclass(frozen=True)
class Entry:
    hash: int
    offset: int
    length: int
    name: str | None


class MixFile:
    def __init__(self, path: Path, names: NameDatabase | None = None, data: bytes | None = None):

        self.path = Path(path)
        self.data = data if data is not None else self.path.read_bytes()
        d = self.data

        (first,) = struct.unpack_from("<H", d, 0)
        self.is_td_format = first != 0
        self.encrypted = False
        if self.is_td_format:
            header = d
            header_pos = 0
            header_len_prefix = 0
        else:
            (flags,) = struct.unpack_from("<H", d, 2)
            self.encrypted = bool(flags & 0x2)
            header_len_prefix = 4
            if self.encrypted:
                header, self.data_start = self._decrypt_header(d)
                header_pos = 0
            else:
                header = d
                header_pos = 4

        (num_files, _data_size) = struct.unpack_from("<HI", header, header_pos)
        if not self.encrypted:
            self.data_start = header_len_prefix + 6 + num_files * _ENTRY.size

        entries: list[Entry] = []
        pos = header_pos + 6
        for _ in range(num_files):
            h, off, ln = _ENTRY.unpack_from(header, pos)
            pos += _ENTRY.size
            name = names.lookup(h) if names else None
            entries.append(Entry(h, self.data_start + off, ln, name))

        self.entries = entries
        self._by_name = {e.name.lower(): e for e in entries if e.name}
        self._by_hash = {e.hash: e for e in entries}

    @staticmethod
    def _decrypt_header(d: bytes) -> tuple[bytes, int]:
        keyblock = d[4:84]
        fish = Blowfish(decrypt_blowfish_key(keyblock))
        first = fish.decrypt(d[84:92])
        (num_files,) = struct.unpack_from("<H", first, 0)
        block_count = (13 + num_files * _ENTRY.size) // 8
        header = fish.decrypt(d[84:84 + block_count * 8])
        data_start = 84 + block_count * 8
        return header, data_start

    @property
    def unresolved(self) -> int:
        return sum(1 for e in self.entries if e.name is None)

    def __contains__(self, name: str) -> bool:
        return name.lower() in self._by_name or classic_hash(name) in self._by_hash

    def entry(self, name: str) -> Entry | None:
        e = self._by_name.get(name.lower())
        if e is None:
            e = self._by_hash.get(classic_hash(name))
        return e

    def read(self, name: str) -> bytes:
        e = self.entry(name)
        if e is None:
            raise KeyError(f"{name} nicht in {self.path.name}")
        return self.data[e.offset:e.offset + e.length]

    def names(self) -> list[str]:
        return sorted(e.name for e in self.entries if e.name)


class ContentSet:


    def __init__(self, content_dir: Path, names: NameDatabase):
        self.root = Path(content_dir)
        self.names = names
        self.mixes: list[MixFile] = []

        paths = [p for p in self.root.rglob("*") if p.is_file() and p.suffix.lower() == ".mix"]
        for p in sorted(paths, key=lambda p: str(p).lower()):
            self._add(MixFile(p, names))

    def _add(self, mix: MixFile) -> None:

        self.mixes.append(mix)
        for e in mix.entries:
            if e.name and e.name.lower().endswith(".mix"):
                inner = mix.data[e.offset:e.offset + e.length]
                try:
                    self._add(MixFile(mix.path.parent / e.name, self.names, data=inner))
                except Exception as ex:
                    print(f"Warnung: {mix.path.name}/{e.name} nicht lesbar: {ex}", file=sys.stderr)

    def find(self, name: str) -> tuple[MixFile, Entry] | None:
        for m in self.mixes:
            e = m.entry(name)
            if e is not None:
                return m, e
        return None

    def read(self, name: str) -> bytes:
        hit = self.find(name)
        if hit is None:
            raise KeyError(f"{name} in keinem MIX unter {self.root}")
        m, e = hit
        return m.data[e.offset:e.offset + e.length]

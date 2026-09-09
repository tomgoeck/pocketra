

import struct

from ._bfconst import P_INIT, S_INIT

_M = 0xFFFFFFFF


class Blowfish:
    def __init__(self, key: bytes):
        if not key:
            raise ValueError("leerer Schlüssel")
        self.P = list(P_INIT)
        self.S = [list(box) for box in S_INIT]

        j = 0
        for i in range(18):
            k = 0
            for _ in range(4):
                k = (k << 8) | key[j % len(key)]
                j += 1
            self.P[i] ^= k

        l = r = 0
        for i in range(0, 18, 2):
            l, r = self._encrypt_words(l, r)
            self.P[i], self.P[i + 1] = l, r
        for box in self.S:
            for i in range(0, 256, 2):
                l, r = self._encrypt_words(l, r)
                box[i], box[i + 1] = l, r

    def _f(self, x: int) -> int:
        S = self.S
        return ((((S[0][x >> 24] + S[1][(x >> 16) & 0xFF]) & _M)
                 ^ S[2][(x >> 8) & 0xFF]) + S[3][x & 0xFF]) & _M

    def _encrypt_words(self, l: int, r: int) -> tuple[int, int]:
        P = self.P
        for i in range(16):
            l ^= P[i]
            r ^= self._f(l)
            l, r = r, l
        l, r = r, l
        r ^= P[16]
        l ^= P[17]
        return l, r

    def _decrypt_words(self, l: int, r: int) -> tuple[int, int]:
        P = self.P
        for i in range(17, 1, -1):
            l ^= P[i]
            r ^= self._f(l)
            l, r = r, l
        l, r = r, l
        r ^= P[1]
        l ^= P[0]
        return l, r

    def decrypt(self, data: bytes) -> bytes:
        if len(data) % 8:
            raise ValueError("Länge kein Vielfaches von 8")
        out = bytearray()
        for off in range(0, len(data), 8):
            l, r = struct.unpack_from(">II", data, off)
            l, r = self._decrypt_words(l, r)
            out += struct.pack(">II", l, r)
        return bytes(out)

    def encrypt(self, data: bytes) -> bytes:
        if len(data) % 8:
            raise ValueError("Länge kein Vielfaches von 8")
        out = bytearray()
        for off in range(0, len(data), 8):
            l, r = struct.unpack_from(">II", data, off)
            l, r = self._encrypt_words(l, r)
            out += struct.pack(">II", l, r)
        return bytes(out)

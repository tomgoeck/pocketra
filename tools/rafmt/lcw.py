

def lcw_decode(src: bytes, pos: int, dest: bytearray) -> int:

    n = len(dest)
    d = 0
    while True:
        cmd = src[pos]
        pos += 1
        if cmd & 0x80 == 0:

            second = src[pos]
            pos += 1
            count = ((cmd & 0x70) >> 4) + 3
            rpos = ((cmd & 0x0F) << 8) + second
            if d + count > n:
                return d
            s = d - rpos
            for i in range(count):
                dest[d + i] = dest[d - 1] if (d - s) == 1 else dest[s + i]
            d += count
        elif cmd & 0x40 == 0:

            count = cmd & 0x3F
            if count == 0:
                return d
            dest[d:d + count] = src[pos:pos + count]
            pos += count
            d += count
        else:
            count3 = cmd & 0x3F
            if count3 == 0x3E:

                count = src[pos] | (src[pos + 1] << 8)
                color = src[pos + 2]
                pos += 3
                dest[d:d + count] = bytes((color,)) * count
                d += count
            else:

                if count3 == 0x3F:
                    count = src[pos] | (src[pos + 1] << 8)
                    pos += 2
                else:
                    count = count3 + 3
                s = src[pos] | (src[pos + 1] << 8)
                pos += 2
                if s >= d:
                    raise ValueError(f"LCW: Quellindex {s} >= Zielindex {d}")
                for _ in range(count):
                    dest[d] = dest[s]
                    d += 1
                    s += 1


def xor_delta_decode(src: bytes, pos: int, dest: bytearray) -> int:

    d = 0
    while True:
        cmd = src[pos]
        pos += 1
        if cmd & 0x80 == 0:
            count = cmd & 0x7F
            if count == 0:

                count = src[pos]
                value = src[pos + 1]
                pos += 2
                for _ in range(count):
                    dest[d] ^= value
                    d += 1
            else:

                for _ in range(count):
                    dest[d] ^= src[pos]
                    pos += 1
                    d += 1
        else:
            count = cmd & 0x7F
            if count == 0:
                count = src[pos] | (src[pos + 1] << 8)
                pos += 2
                if count == 0:
                    return d
                if count & 0x8000 == 0:
                    d += count & 0x7FFF
                elif count & 0x4000 == 0:
                    for _ in range(count & 0x3FFF):
                        dest[d] ^= src[pos]
                        pos += 1
                        d += 1
                else:
                    value = src[pos]
                    pos += 1
                    for _ in range(count & 0x3FFF):
                        dest[d] ^= value
                        d += 1
            else:
                d += count

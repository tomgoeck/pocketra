

import base64


_PUBLIC_KEY_DER = base64.b64decode(
    "AihRvNoIbTn85FZRYNZRcT+i6KpU+maCsEqr3Q5q+LDB5tH7Tz2qQ38V"
)
_EXPONENT = 0x10001


def _modulus() -> int:
    der = _PUBLIC_KEY_DER
    if der[0] != 0x02:
        raise ValueError("öffentlicher Schlüssel: kein DER-INTEGER")
    length = der[1]
    if length & 0x80:
        n = length & 0x7F
        length = int.from_bytes(der[2:2 + n], "big")
        body = der[2 + n:2 + n + length]
    else:
        body = der[2:2 + length]
    return int.from_bytes(body, "big")


_MODULUS = _modulus()


def decrypt_blowfish_key(keyblock: bytes) -> bytes:

    if len(keyblock) < 80:
        raise ValueError("Schlüsselblock zu kurz")

    key_bits = _MODULUS.bit_length() - 1
    a = (key_bits - 1) // 8
    pre_len = (55 // a + 1) * (a + 1)

    out = bytearray()
    src = 0
    while a + 1 <= pre_len:
        block = int.from_bytes(keyblock[src:src + a + 1], "little")
        value = pow(block, _EXPONENT, _MODULUS)
        out += value.to_bytes(a + 8, "little")[:a]
        pre_len -= a + 1
        src += a + 1

    return bytes(out[:56])

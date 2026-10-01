#include "blowfish.h"

#include <algorithm>
#include <cstring>

#include "blowfish_const.h"

namespace racontent {

Blowfish::Blowfish(const uint8_t* key, size_t key_len) {
    std::memcpy(P, BF_P_INIT, sizeof(P));
    std::memcpy(S, BF_S_INIT, sizeof(S));
    if (key_len == 0) {
        return;
    }

    size_t j = 0;
    for (int i = 0; i < 18; ++i) {
        uint32_t k = 0;
        for (int b = 0; b < 4; ++b) {
            k = (k << 8) | key[j % key_len];
            ++j;
        }
        P[i] ^= k;
    }

    uint32_t l = 0, r = 0;
    for (int i = 0; i < 18; i += 2) {
        encrypt_words(l, r);
        P[i] = l;
        P[i + 1] = r;
    }
    for (int box = 0; box < 4; ++box) {
        for (int i = 0; i < 256; i += 2) {
            encrypt_words(l, r);
            S[box][i] = l;
            S[box][i + 1] = r;
        }
    }
}

uint32_t Blowfish::f(uint32_t x) const {
    return (((S[0][x >> 24] + S[1][(x >> 16) & 0xFF]) ^ S[2][(x >> 8) & 0xFF]) + S[3][x & 0xFF]);
}

void Blowfish::encrypt_words(uint32_t& l, uint32_t& r) const {
    for (int i = 0; i < 16; ++i) {
        l ^= P[i];
        r ^= f(l);
        std::swap(l, r);
    }
    std::swap(l, r);
    r ^= P[16];
    l ^= P[17];
}

void Blowfish::decrypt_words(uint32_t& l, uint32_t& r) const {
    for (int i = 17; i > 1; --i) {
        l ^= P[i];
        r ^= f(l);
        std::swap(l, r);
    }
    std::swap(l, r);
    r ^= P[1];
    l ^= P[0];
}

static inline uint32_t be32(const uint8_t* p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}

static inline void put_be32(uint8_t* p, uint32_t v) {
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

void Blowfish::decrypt(uint8_t* data, size_t len) const {
    for (size_t off = 0; off + 8 <= len; off += 8) {
        uint32_t l = be32(data + off), r = be32(data + off + 4);
        decrypt_words(l, r);
        put_be32(data + off, l);
        put_be32(data + off + 4, r);
    }
}

void Blowfish::encrypt(uint8_t* data, size_t len) const {
    for (size_t off = 0; off + 8 <= len; off += 8) {
        uint32_t l = be32(data + off), r = be32(data + off + 4);
        encrypt_words(l, r);
        put_be32(data + off, l);
        put_be32(data + off + 4, r);
    }
}


namespace {


using Big = std::vector<uint32_t>;

void trim(Big& a) {
    while (!a.empty() && a.back() == 0) {
        a.pop_back();
    }
}

int cmp(const Big& a, const Big& b) {
    if (a.size() != b.size()) {
        return a.size() < b.size() ? -1 : 1;
    }
    for (size_t i = a.size(); i-- > 0;) {
        if (a[i] != b[i]) {
            return a[i] < b[i] ? -1 : 1;
        }
    }
    return 0;
}


void sub_in_place(Big& a, const Big& b) {
    uint64_t borrow = 0;
    for (size_t i = 0; i < a.size(); ++i) {
        uint64_t bi = i < b.size() ? b[i] : 0;
        uint64_t cur = (uint64_t)a[i] - bi - borrow;
        a[i] = (uint32_t)cur;
        borrow = (cur >> 32) ? 1 : 0;
    }
    trim(a);
}

void shift_left_1(Big& a) {
    uint32_t carry = 0;
    for (size_t i = 0; i < a.size(); ++i) {
        uint32_t next = a[i] >> 31;
        a[i] = (a[i] << 1) | carry;
        carry = next;
    }
    if (carry) {
        a.push_back(carry);
    }
}

bool bit(const Big& a, size_t i) {
    const size_t limb = i / 32;
    return limb < a.size() && ((a[limb] >> (i % 32)) & 1u) != 0;
}

size_t bit_length(const Big& a) {
    if (a.empty()) {
        return 0;
    }
    uint32_t top = a.back();
    size_t n = (a.size() - 1) * 32;
    while (top) {
        ++n;
        top >>= 1;
    }
    return n;
}

Big mul(const Big& a, const Big& b) {
    if (a.empty() || b.empty()) {
        return Big();
    }
    Big out(a.size() + b.size(), 0);
    for (size_t i = 0; i < a.size(); ++i) {
        uint64_t carry = 0;
        for (size_t j = 0; j < b.size(); ++j) {
            uint64_t cur = (uint64_t)a[i] * b[j] + out[i + j] + carry;
            out[i + j] = (uint32_t)cur;
            carry = cur >> 32;
        }
        size_t k = i + b.size();
        while (carry) {
            uint64_t cur = (uint64_t)out[k] + carry;
            out[k] = (uint32_t)cur;
            carry = cur >> 32;
            ++k;
        }
    }
    trim(out);
    return out;
}


Big mod(const Big& a, const Big& m) {
    if (cmp(a, m) < 0) {
        return a;
    }
    Big rem;
    for (size_t i = bit_length(a); i-- > 0;) {
        shift_left_1(rem);
        if (bit(a, i)) {
            if (rem.empty()) {
                rem.push_back(1);
            } else {
                rem[0] |= 1u;
            }
        }
        if (cmp(rem, m) >= 0) {
            sub_in_place(rem, m);
        }
    }
    trim(rem);
    return rem;
}

Big mod_pow(const Big& base, uint32_t exp, const Big& m) {
    Big result{1};
    Big b = mod(base, m);
    while (exp) {
        if (exp & 1u) {
            result = mod(mul(result, b), m);
        }
        exp >>= 1;
        if (exp) {
            b = mod(mul(b, b), m);
        }
    }
    trim(result);
    return result;
}

Big from_le(const uint8_t* p, size_t len) {
    Big out((len + 3) / 4, 0);
    for (size_t i = 0; i < len; ++i) {
        out[i / 4] |= (uint32_t)p[i] << (8 * (i % 4));
    }
    trim(out);
    return out;
}

Big from_be(const uint8_t* p, size_t len) {
    Big out((len + 3) / 4, 0);
    for (size_t i = 0; i < len; ++i) {
        const size_t rev = len - 1 - i;
        out[rev / 4] |= (uint32_t)p[i] << (8 * (rev % 4));
    }
    trim(out);
    return out;
}

void to_le(const Big& a, uint8_t* out, size_t len) {
    for (size_t i = 0; i < len; ++i) {
        const size_t limb = i / 4;
        out[i] = limb < a.size() ? (uint8_t)(a[limb] >> (8 * (i % 4))) : 0;
    }
}


const uint8_t PUBLIC_KEY_DER[] = {
    0x02, 0x28, 0x51, 0xBC, 0xDA, 0x08, 0x6D, 0x39, 0xFC, 0xE4, 0x56, 0x51, 0x60, 0xD6,
    0x51, 0x71, 0x3F, 0xA2, 0xE8, 0xAA, 0x54, 0xFA, 0x66, 0x82, 0xB0, 0x4A, 0xAB, 0xDD,
    0x0E, 0x6A, 0xF8, 0xB0, 0xC1, 0xE6, 0xD1, 0xFB, 0x4F, 0x3D, 0xAA, 0x43, 0x7F, 0x15,
};

Big modulus() {
    const uint8_t* der = PUBLIC_KEY_DER;

    const size_t length = der[1];
    return from_be(der + 2, length);
}

}

std::vector<uint8_t> decrypt_blowfish_key(const uint8_t* keyblock, size_t len) {
    if (len < 80) {
        return {};
    }
    const Big m = modulus();
    const size_t key_bits = bit_length(m) - 1;
    const size_t a = (key_bits - 1) / 8;
    if (a == 0) {
        return {};
    }
    size_t pre_len = (55 / a + 1) * (a + 1);

    std::vector<uint8_t> out;
    size_t src = 0;
    while (a + 1 <= pre_len && src + a + 1 <= len) {
        const Big block = from_le(keyblock + src, a + 1);
        const Big value = mod_pow(block, 0x10001u, m);
        std::vector<uint8_t> buf(a + 8, 0);
        to_le(value, buf.data(), buf.size());
        out.insert(out.end(), buf.begin(), buf.begin() + a);
        pre_len -= a + 1;
        src += a + 1;
    }
    if (out.size() > 56) {
        out.resize(56);
    }
    return out;
}

}

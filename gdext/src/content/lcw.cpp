#include "lcw.h"

namespace racontent {


#define RA_NEED(n)                     \
    do {                               \
        if (pos + (n) > src_len) {     \
            return -1;                 \
        }                              \
    } while (0)

long lcw_decode(const uint8_t* src, size_t src_len, size_t pos, uint8_t* dest, size_t dest_len,
                bool relative) {
    const size_t n = dest_len;
    size_t d = 0;
    while (true) {
        RA_NEED(1);
        const uint8_t cmd = src[pos++];
        if ((cmd & 0x80) == 0) {

            RA_NEED(1);
            const uint8_t second = src[pos++];
            const size_t count = ((cmd & 0x70) >> 4) + 3;
            const size_t rpos = ((size_t)(cmd & 0x0F) << 8) + second;
            if (d + count > n) {
                return (long)d;
            }
            if (rpos > d) {
                return -1;
            }
            const size_t s = d - rpos;
            for (size_t i = 0; i < count; ++i) {
                dest[d + i] = (rpos == 1) ? dest[d - 1] : dest[s + i];
            }
            d += count;
        } else if ((cmd & 0x40) == 0) {

            const size_t count = cmd & 0x3F;
            if (count == 0) {
                return (long)d;
            }
            RA_NEED(count);
            if (d + count > n) {
                return -1;
            }
            for (size_t i = 0; i < count; ++i) {
                dest[d + i] = src[pos + i];
            }
            pos += count;
            d += count;
        } else {
            const size_t count3 = cmd & 0x3F;
            if (count3 == 0x3E) {

                RA_NEED(3);
                const size_t count = (size_t)src[pos] | ((size_t)src[pos + 1] << 8);
                const uint8_t color = src[pos + 2];
                pos += 3;
                if (d + count > n) {
                    return -1;
                }
                for (size_t i = 0; i < count; ++i) {
                    dest[d + i] = color;
                }
                d += count;
            } else {

                size_t count;
                if (count3 == 0x3F) {
                    RA_NEED(2);
                    count = (size_t)src[pos] | ((size_t)src[pos + 1] << 8);
                    pos += 2;
                } else {
                    count = count3 + 3;
                }
                RA_NEED(2);
                const size_t word = (size_t)src[pos] | ((size_t)src[pos + 1] << 8);
                pos += 2;
                if (relative && word > d) {
                    return -1;
                }
                size_t s = relative ? d - word : word;
                if (s >= d) {
                    return -1;
                }
                if (d + count > n) {
                    return -1;
                }
                for (size_t i = 0; i < count; ++i) {
                    dest[d++] = dest[s++];
                }
            }
        }
    }
}

long xor_delta_decode(const uint8_t* src, size_t src_len, size_t pos, uint8_t* dest, size_t dest_len) {
    size_t d = 0;
    while (true) {
        RA_NEED(1);
        const uint8_t cmd = src[pos++];
        if ((cmd & 0x80) == 0) {
            size_t count = cmd & 0x7F;
            if (count == 0) {

                RA_NEED(2);
                count = src[pos];
                const uint8_t value = src[pos + 1];
                pos += 2;
                if (d + count > dest_len) {
                    return -1;
                }
                for (size_t i = 0; i < count; ++i) {
                    dest[d++] ^= value;
                }
            } else {

                RA_NEED(count);
                if (d + count > dest_len) {
                    return -1;
                }
                for (size_t i = 0; i < count; ++i) {
                    dest[d++] ^= src[pos++];
                }
            }
        } else {
            size_t count = cmd & 0x7F;
            if (count == 0) {
                RA_NEED(2);
                const uint32_t big = (uint32_t)src[pos] | ((uint32_t)src[pos + 1] << 8);
                pos += 2;
                if (big == 0) {
                    return (long)d;
                }
                if ((big & 0x8000) == 0) {
                    d += big & 0x7FFF;
                } else if ((big & 0x4000) == 0) {
                    const size_t c = big & 0x3FFF;
                    RA_NEED(c);
                    if (d + c > dest_len) {
                        return -1;
                    }
                    for (size_t i = 0; i < c; ++i) {
                        dest[d++] ^= src[pos++];
                    }
                } else {
                    RA_NEED(1);
                    const uint8_t value = src[pos++];
                    const size_t c = big & 0x3FFF;
                    if (d + c > dest_len) {
                        return -1;
                    }
                    for (size_t i = 0; i < c; ++i) {
                        dest[d++] ^= value;
                    }
                }
            } else {
                d += count;
            }
        }
        if (d > dest_len) {
            return -1;
        }
    }
}

#undef RA_NEED

}

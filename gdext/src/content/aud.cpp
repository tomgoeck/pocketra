#include "aud.h"

#include <cstring>

namespace racontent {

namespace {

const int IMA_INDEX_ADJUST[8] = {-1, -1, -1, -1, 2, 4, 6, 8};
const int IMA_STEP[89] = {
    7,     8,     9,     10,    11,    12,    13,    14,    16,    17,    19,    21,    23,
    25,    28,    31,    34,    37,    41,    45,    50,    55,    60,    66,    73,    80,
    88,    97,    107,   118,   130,   143,   157,   173,   190,   209,   230,   253,   279,
    307,   337,   371,   408,   449,   494,   544,   598,   658,   724,   796,   876,   963,
    1060,  1166,  1282,  1411,  1552,  1707,  1878,  2066,  2272,  2499,  2749,  3024,  3327,
    3660,  4026,  4428,  4871,  5358,  5894,  6484,  7132,  7845,  8630,  9493,  10442, 11487,
    12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
};

const int WS_STEP2[4] = {-2, -1, 0, 1};
const int WS_STEP4[16] = {-9, -8, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 8};


int16_t ima_sample(uint8_t b, int& index, int& current) {
    const int step = IMA_STEP[index];
    const int nibble = b & 0x0F;
    const int delta = nibble & 7;
    int next = index + IMA_INDEX_ADJUST[delta];
    if (next < 0) {
        next = 0;
    }
    if (next > 88) {
        next = 88;
    }
    const int diff = ((2 * delta + 1) * step) >> 3;
    current += (nibble & 8) ? -diff : diff;
    if (current > 32767) {
        current = 32767;
    }
    if (current < -32768) {
        current = -32768;
    }
    index = next;
    return (int16_t)current;
}

inline int clamp_u8(int v) { return v < 0 ? 0 : (v > 255 ? 255 : v); }


void ws_decode(const uint8_t* input, size_t in_len, uint8_t* output, size_t out_len) {
    if (in_len == out_len) {
        std::memcpy(output, input, in_len);
        return;
    }
    int sample = 0x80;
    size_t r = 0, w = 0;
    while (r < in_len && w < out_len) {
        const uint8_t cmd = input[r++];
        int count = cmd & 0x3F;
        switch (cmd >> 6) {
            case 0:
                for (++count; count > 0 && r < in_len && w + 4 <= out_len; --count) {
                    const uint8_t code = input[r++];
                    for (int shift = 0; shift < 8; shift += 2) {
                        sample = clamp_u8(sample + WS_STEP2[(code >> shift) & 0x03]);
                        output[w++] = (uint8_t)sample;
                    }
                }
                break;
            case 1:
                for (++count; count > 0 && r < in_len && w + 2 <= out_len; --count) {
                    const uint8_t code = input[r++];
                    sample = clamp_u8(sample + WS_STEP4[code & 0x0F]);
                    output[w++] = (uint8_t)sample;
                    sample = clamp_u8(sample + WS_STEP4[(code >> 4) & 0x0F]);
                    output[w++] = (uint8_t)sample;
                }
                break;
            case 2:
                if (count & 0x20) {

                    const int delta = (int)(int8_t)((int8_t)(count << 3)) >> 3;
                    sample += delta;
                    output[w++] = (uint8_t)sample;
                } else {
                    for (++count; count > 0 && r < in_len && w < out_len; --count) {
                        output[w++] = input[r++];
                    }
                    if (r > 0) {
                        sample = input[r - 1];
                    }
                }
                break;
            default:
                for (++count; count > 0 && w < out_len; --count) {
                    output[w++] = (uint8_t)sample;
                }
                break;
        }
    }
    while (w < out_len) {
        output[w++] = (uint8_t)sample;
    }
}

inline uint16_t le16(const uint8_t* p) { return (uint16_t)(p[0] | (p[1] << 8)); }
inline uint32_t le32(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

}

bool aud_probe(const uint8_t* raw, size_t len, int& sample_rate, int& channels, int& bits, int& format,
               uint32_t& output_size) {
    if (len < 12) {
        return false;
    }
    sample_rate = le16(raw);
    output_size = le32(raw + 6);
    const uint8_t flags = raw[10];
    bits = (flags & 0x2) ? 16 : 8;
    channels = (flags & 0x1) ? 2 : 1;
    format = raw[11];
    return (format == 1 || format == 99) && sample_rate > 0;
}

bool decode_aud(const uint8_t* raw, size_t len, AudClip& out, std::string& error) {
    uint32_t output_size = 0;
    int format = 0;
    if (!aud_probe(raw, len, out.sample_rate, out.channels, out.bits, format, output_size)) {
        error = "AUD: unbekanntes Format";
        return false;
    }
    int32_t data_size = (int32_t)le32(raw + 2);
    out.bits = format == 99 ? 16 : 8;
    out.pcm.clear();
    out.pcm.reserve(output_size);

    size_t pos = 12;
    int index = 0, current = 0;
    uint32_t written = 0;
    while (data_size > 0 && pos + 8 <= len) {
        const uint16_t comp = le16(raw + pos);
        const uint16_t osize = le16(raw + pos + 2);
        const uint32_t magic = le32(raw + pos + 4);
        if (magic != 0xDEAF) {
            break;
        }
        pos += 8;
        if (pos + comp > len) {
            break;
        }
        if (format == 99) {
            for (uint16_t n = 0; n < comp; ++n) {
                const uint8_t b = raw[pos + n];
                int16_t t = ima_sample(b, index, current);
                out.pcm.push_back((uint8_t)t);
                out.pcm.push_back((uint8_t)(t >> 8));
                written += 2;
                if (written < output_size) {

                    t = ima_sample((uint8_t)(b >> 4), index, current);
                    out.pcm.push_back((uint8_t)t);
                    out.pcm.push_back((uint8_t)(t >> 8));
                    written += 2;
                }
            }
        } else {
            const size_t before = out.pcm.size();
            out.pcm.resize(before + osize);
            ws_decode(raw + pos, comp, out.pcm.data() + before, osize);
            written += osize;
        }
        pos += comp;
        data_size -= 8 + (int32_t)comp;
    }
    if (out.pcm.empty()) {
        error = "AUD: keine Daten";
        return false;
    }
    return true;
}

void pcm_to_wav(const AudClip& clip, std::vector<uint8_t>& out) {
    const uint32_t data_len = (uint32_t)clip.pcm.size();
    const uint16_t block_align = (uint16_t)(clip.channels * clip.bits / 8);
    const uint32_t byte_rate = (uint32_t)clip.sample_rate * block_align;
    out.clear();
    out.reserve(44 + data_len);
    auto put = [&out](const char* s, size_t n) {
        for (size_t i = 0; i < n; ++i) {
            out.push_back((uint8_t)s[i]);
        }
    };
    auto put32 = [&out](uint32_t v) {
        out.push_back((uint8_t)v);
        out.push_back((uint8_t)(v >> 8));
        out.push_back((uint8_t)(v >> 16));
        out.push_back((uint8_t)(v >> 24));
    };
    auto put16 = [&out](uint16_t v) {
        out.push_back((uint8_t)v);
        out.push_back((uint8_t)(v >> 8));
    };
    put("RIFF", 4);
    put32(36 + data_len);
    put("WAVEfmt ", 8);
    put32(16);
    put16(1);
    put16((uint16_t)clip.channels);
    put32((uint32_t)clip.sample_rate);
    put32(byte_rate);
    put16(block_align);
    put16((uint16_t)clip.bits);
    put("data", 4);
    put32(data_len);
    out.insert(out.end(), clip.pcm.begin(), clip.pcm.end());
}


bool AudStreamDecoder::open(std::vector<uint8_t> data, std::string& error) {
    data_ = std::move(data);
    if (!aud_probe(data_.data(), data_.size(), sample_rate_, channels_, bits_, format_, output_size_)) {
        error = "AUD: unbekanntes Format";
        return false;
    }
    bits_ = format_ == 99 ? 16 : 8;
    first_ = 12;
    rewind();
    return true;
}

void AudStreamDecoder::rewind() {
    pos_ = first_;
    index_ = 0;
    current_ = 0;
    written_ = 0;
}

double AudStreamDecoder::length_seconds() const {
    const int bytes = (bits_ / 8) * channels_;
    if (sample_rate_ <= 0 || bytes <= 0) {
        return 0.0;
    }
    return (double)output_size_ / (double)bytes / (double)sample_rate_;
}

bool AudStreamDecoder::next_block(std::vector<uint8_t>& out) {
    out.clear();
    if (pos_ + 8 > data_.size()) {
        return false;
    }
    const uint16_t comp = le16(data_.data() + pos_);
    const uint16_t osize = le16(data_.data() + pos_ + 2);
    const uint32_t magic = le32(data_.data() + pos_ + 4);
    if (magic != 0xDEAF) {
        return false;
    }
    const size_t body = pos_ + 8;
    if (body + comp > data_.size()) {
        return false;
    }
    if (format_ == 99) {
        out.reserve((size_t)comp * 4);
        for (uint16_t n = 0; n < comp; ++n) {
            const uint8_t b = data_[body + n];
            int16_t t = ima_sample(b, index_, current_);
            out.push_back((uint8_t)t);
            out.push_back((uint8_t)(t >> 8));
            written_ += 2;
            if (written_ < output_size_) {
                t = ima_sample((uint8_t)(b >> 4), index_, current_);
                out.push_back((uint8_t)t);
                out.push_back((uint8_t)(t >> 8));
                written_ += 2;
            }
        }
    } else {
        out.resize(osize);
        ws_decode(data_.data() + body, comp, out.data(), osize);
        written_ += osize;
    }
    pos_ = body + comp;
    return !out.empty();
}

}

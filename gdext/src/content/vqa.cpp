#include "vqa.h"

#include <algorithm>
#include <cstring>

#include "lcw.h"

namespace racontent {

namespace {

inline uint16_t le16(const uint8_t* p) { return (uint16_t)(p[0] | (p[1] << 8)); }
inline uint32_t le32(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

inline uint32_t be32(const uint8_t* p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}

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


void ima_expand(const std::vector<uint8_t>& in, std::vector<uint8_t>& out) {
    int index = 0, current = 0;
    out.clear();
    out.reserve(in.size() * 4);
    for (uint8_t b : in) {
        int16_t t = ima_sample(b, index, current);
        out.push_back((uint8_t)t);
        out.push_back((uint8_t)(t >> 8));
        t = ima_sample((uint8_t)(b >> 4), index, current);
        out.push_back((uint8_t)t);
        out.push_back((uint8_t)(t >> 8));
    }
}

}

bool VqaDecoder::open(std::vector<uint8_t> data, std::string& error) {
    data_ = std::move(data);
    if (!parse_header(error)) {
        return false;
    }
    if (!collect_audio(error)) {
        return false;
    }
    current_ = -1;
    return true;
}

bool VqaDecoder::parse_header(std::string& error) {
    const uint8_t* d = data_.data();
    const size_t n = data_.size();
    if (n < 64 || std::memcmp(d, "FORM", 4) != 0) {
        error = "VQA: kein FORM-Block";
        return false;
    }
    if (std::memcmp(d + 8, "WVQAVQHD", 8) != 0) {
        error = "VQA: kein WVQAVQHD";
        return false;
    }
    size_t pos = 20;

    video_flags_ = le16(d + pos + 2);
    frame_count_ = le16(d + pos + 4);
    width_ = le16(d + pos + 6);
    height_ = le16(d + pos + 8);
    block_w_ = d[pos + 10];
    block_h_ = d[pos + 11];
    framerate_ = d[pos + 12];
    chunk_buffer_parts_ = d[pos + 13];
    num_colors_ = le16(d + pos + 14);

    audio_rate_ = le16(d + pos + 24);
    audio_channels_ = d[pos + 26];
    audio_bits_ = d[pos + 27];
    pos += 42;

    if (width_ <= 0 || height_ <= 0 || block_w_ <= 0 || block_h_ <= 0 || frame_count_ <= 0) {
        error = "VQA: unbrauchbarer Kopf";
        return false;
    }
    if (video_flags_ & 0x10) {
        error = "VQA: 16-Bit-HQ-Variante wird nicht unterstützt";
        return false;
    }
    blocks_x_ = width_ / block_w_;
    blocks_y_ = height_ / block_h_;


    while (pos + 8 <= n && std::memcmp(d + pos, "FINF", 4) != 0) {
        if (d[pos + 3] != 'F') {
            error = "VQA: unbekannter Block im Kopf";
            return false;
        }
        const uint32_t jmp = be32(d + pos + 4);
        pos += 8 + jmp;
    }
    if (pos + 8 > n) {
        error = "VQA: kein FINF-Block";
        return false;
    }
    pos += 8;

    offsets_.resize(frame_count_);
    for (int i = 0; i < frame_count_; ++i) {
        if (pos + 4 > n) {
            error = "VQA: Frametabelle unvollständig";
            return false;
        }
        uint32_t off = le32(d + pos);
        pos += 4;
        if (off > 0x40000000u) {
            off -= 0x40000000u;
        }
        offsets_[i] = off << 1;
    }

    cbf_buffer_.assign((size_t)width_ * height_, 0);
    cbf_.assign((size_t)width_ * height_, 0);
    cbp_.assign((size_t)width_ * height_, 0);
    orig_.assign((size_t)2 * blocks_x_ * blocks_y_, 0);
    palette_.assign(1024, 0);
    for (int i = 0; i < 256; ++i) {
        palette_[i * 4 + 3] = 255;
    }
    frame_.assign((size_t)width_ * height_, 0);
    return true;
}

bool VqaDecoder::collect_audio(std::string& error) {
    const uint8_t* d = data_.data();
    const size_t n = data_.size();
    std::vector<uint8_t> left, right;
    bool compressed = false;
    if (audio_channels_ == 0) {
        audio_.clear();
        return true;
    }

    for (int i = 0; i < frame_count_; ++i) {
        size_t pos = offsets_[i];
        const size_t end = (i < frame_count_ - 1) ? offsets_[i + 1] : n;
        while (pos + 8 <= n && pos < end) {
            char type[5] = {0};
            std::memcpy(type, d + pos, 4);
            pos += 4;
            if (std::memcmp(type, "SN2J", 4) == 0) {
                const uint32_t jmp = be32(d + pos);
                pos += 4 + jmp;
                if (pos + 8 > n) {
                    break;
                }
                std::memcpy(type, d + pos, 4);
                pos += 4;
            }
            const uint32_t length = be32(d + pos);
            pos += 4;
            if (pos + length > n) {
                break;
            }
            if (std::memcmp(type, "SND0", 4) == 0 || std::memcmp(type, "SND2", 4) == 0) {
                if (audio_channels_ == 1) {
                    left.insert(left.end(), d + pos, d + pos + length);
                    pos += length;
                } else {
                    const uint32_t half = length / 2;
                    left.insert(left.end(), d + pos, d + pos + half);
                    right.insert(right.end(), d + pos + half, d + pos + 2 * half);
                    pos += length + (length % 2 ? 2 : 0);
                }
                compressed = std::memcmp(type, "SND2", 4) == 0;
            } else {
                pos += length;
            }

            if (pos < n && d[pos] == 0) {
                ++pos;
            }
        }
    }

    if (audio_channels_ == 1) {
        if (compressed) {
            ima_expand(left, audio_);
        } else {
            audio_ = left;
        }
    } else {
        std::vector<uint8_t> l, r;
        if (compressed) {
            ima_expand(left, l);
            ima_expand(right, r);
        } else {
            l = left;
            r = right;
        }
        const size_t frames = (l.size() < r.size() ? l.size() : r.size()) / 2;
        audio_.resize(frames * 4);
        for (size_t i = 0; i < frames; ++i) {
            audio_[i * 4 + 0] = l[i * 2];
            audio_[i * 4 + 1] = l[i * 2 + 1];
            audio_[i * 4 + 2] = r[i * 2];
            audio_[i * 4 + 3] = r[i * 2 + 1];
        }
    }
    (void)error;
    return true;
}

bool VqaDecoder::decode_vqfr(size_t& pos, size_t end, bool is_vqfl, std::string& error) {
    const uint8_t* d = data_.data();
    const size_t n = data_.size();


    if (chunk_buffer_parts_ != 0 && current_chunk_buffer_ == chunk_buffer_parts_) {
        if (!cbp_compressed_) {
            cbf_ = cbp_;
        } else {
            std::fill(cbf_.begin(), cbf_.end(), 0);
            lcw_decode(cbp_.data(), cbp_.size(), 0, cbf_.data(), cbf_.size());
        }
        chunk_buffer_offset_ = 0;
        current_chunk_buffer_ = 0;
    }

    while (pos + 8 <= n) {
        if (d[pos] == 0) {
            ++pos;
        }
        if (pos + 8 > n) {
            break;
        }
        char type[5] = {0};
        std::memcpy(type, d + pos, 4);
        pos += 4;
        const size_t sub_len = be32(d + pos);
        pos += 4;
        if (pos + sub_len > n) {
            error = "VQA: Unterblock reicht über das Dateiende";
            return false;
        }

        if (std::memcmp(type, "CBFZ", 4) == 0) {
            const bool decode_mode = d[pos] == 0;
            std::fill(cbf_.begin(), cbf_.end(), 0);
            std::fill(cbf_buffer_.begin(), cbf_buffer_.end(), 0);
            lcw_decode(d + pos, sub_len, decode_mode ? 1 : 0, cbf_buffer_.data(), cbf_buffer_.size(),
                       decode_mode);
            cbf_ = cbf_buffer_;
            pos += sub_len;
            if (is_vqfl) {
                return true;
            }
        } else if (std::memcmp(type, "CBF0", 4) == 0) {
            cbf_.assign(d + pos, d + pos + sub_len);
            pos += sub_len;
        } else if (std::memcmp(type, "CBP0", 4) == 0 || std::memcmp(type, "CBPZ", 4) == 0) {
            if (chunk_buffer_offset_ + sub_len > cbp_.size()) {
                cbp_.resize(chunk_buffer_offset_ + sub_len);
            }
            std::memcpy(cbp_.data() + chunk_buffer_offset_, d + pos, sub_len);
            chunk_buffer_offset_ += sub_len;
            ++current_chunk_buffer_;
            cbp_compressed_ = std::memcmp(type, "CBPZ", 4) == 0;
            pos += sub_len;
        } else if (std::memcmp(type, "CPL0", 4) == 0) {
            for (int i = 0; i < num_colors_ && (size_t)(pos + 3) <= n; ++i) {
                palette_[i * 4 + 0] = (uint8_t)(d[pos + i * 3 + 0] << 2);
                palette_[i * 4 + 1] = (uint8_t)(d[pos + i * 3 + 1] << 2);
                palette_[i * 4 + 2] = (uint8_t)(d[pos + i * 3 + 2] << 2);
                palette_[i * 4 + 3] = 255;
            }
            pos += sub_len;
        } else if (std::memcmp(type, "VPTZ", 4) == 0) {
            lcw_decode(d + pos, sub_len, 0, orig_.data(), orig_.size());
            pos += sub_len;
            return true;
        } else if (std::memcmp(type, "VPTR", 4) == 0) {
            std::fill(orig_.begin(), orig_.end(), 0);
            std::memcpy(orig_.data(), d + pos, sub_len < orig_.size() ? sub_len : orig_.size());
            pos += sub_len;
            return true;
        } else {
            error = std::string("VQA: unbekannter Unterblock ") + type;
            return false;
        }
        if (pos >= end) {
            break;
        }
    }
    return true;
}

bool VqaDecoder::load_frame(int index, std::string& error) {
    if (index < 0 || index >= frame_count_) {
        return false;
    }
    const uint8_t* d = data_.data();
    const size_t n = data_.size();
    size_t pos = offsets_[index];
    const size_t end = (index < frame_count_ - 1) ? offsets_[index + 1] : n;

    while (pos + 8 <= n && pos < end) {
        char type[5] = {0};
        std::memcpy(type, d + pos, 4);
        pos += 4;
        uint32_t length = 0;
        if (std::memcmp(type, "SN2J", 4) == 0) {
            const uint32_t jmp = be32(d + pos);
            pos += 4 + jmp;
            if (pos + 8 > n) {
                break;
            }
            std::memcpy(type, d + pos, 4);
            pos += 4;
            if (std::memcmp(type, "SND2", 4) == 0) {
                length = be32(d + pos);
                pos += 4 + length;
                if (pos + 8 > n) {
                    break;
                }
                std::memcpy(type, d + pos, 4);
                pos += 4;
            } else {
                error = "VQA: SN2J ohne SND2";
                return false;
            }
        }
        length = be32(d + pos);
        pos += 4;

        if (std::memcmp(type, "VQFR", 4) == 0) {
            if (!decode_vqfr(pos, pos + length, false, error)) {
                return false;
            }
        } else if (std::memcmp(type, "\0VQF", 4) == 0) {
            ++pos;
            if (!decode_vqfr(pos, pos + length, false, error)) {
                return false;
            }
        } else if (std::memcmp(type, "VQFL", 4) == 0) {
            if (!decode_vqfr(pos, pos + length, true, error)) {
                return false;
            }
        } else {
            pos += length;
        }
        if (pos < n && d[pos] == 0) {
            ++pos;
        }
    }

    decode_frame_data();
    current_ = index;
    return true;
}

void VqaDecoder::decode_frame_data() {
    const size_t plane = (size_t)blocks_x_ * blocks_y_;
    for (int y = 0; y < blocks_y_; ++y) {
        for (int x = 0; x < blocks_x_; ++x) {
            const uint8_t px = orig_[(size_t)x + (size_t)y * blocks_x_];
            const uint8_t mod = orig_[(size_t)x + (size_t)y * blocks_x_ + plane];
            for (int j = 0; j < block_h_; ++j) {
                for (int i = 0; i < block_w_; ++i) {
                    const size_t cbfi = ((size_t)mod * 256 + px) * 8 + (size_t)j * block_w_ + i;
                    const uint8_t color = (mod == 0x0F || cbfi >= cbf_.size()) ? px : cbf_[cbfi];
                    const int pixel_x = x * block_w_ + i;
                    const int pixel_y = y * block_h_ + j;
                    frame_[(size_t)pixel_y * width_ + pixel_x] = color;
                }
            }
        }
    }
}

bool VqaDecoder::seek(int frame, std::string& error) {
    if (frame < 0 || frame >= frame_count_) {
        return false;
    }
    if (frame <= current_) {

        std::fill(cbf_.begin(), cbf_.end(), 0);
        std::fill(cbp_.begin(), cbp_.end(), 0);
        std::fill(orig_.begin(), orig_.end(), 0);
        current_chunk_buffer_ = 0;
        chunk_buffer_offset_ = 0;
        cbp_compressed_ = false;
        current_ = -1;
    }
    while (current_ < frame) {
        if (!load_frame(current_ + 1, error)) {
            return false;
        }
    }
    return true;
}

bool VqaDecoder::next_frame(std::string& error) {
    if (current_ + 1 >= frame_count_) {
        return false;
    }
    return load_frame(current_ + 1, error);
}

void VqaDecoder::frame_rgba(std::vector<uint8_t>& out) const {
    out.resize((size_t)width_ * height_ * 4);
    for (size_t i = 0; i < frame_.size(); ++i) {
        const uint8_t c = frame_[i];
        out[i * 4 + 0] = palette_[c * 4 + 0];
        out[i * 4 + 1] = palette_[c * 4 + 1];
        out[i * 4 + 2] = palette_[c * 4 + 2];
        out[i * 4 + 3] = 255;
    }
}

}

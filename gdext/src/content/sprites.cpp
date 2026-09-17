#include "sprites.h"

#include <cstring>

#include "lcw.h"
#include "platform.h"

namespace racontent {

static inline uint16_t le16(const uint8_t* p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static inline uint32_t le32(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

enum : uint8_t { SHP_LCW = 0x80, SHP_XOR_REF = 0x40, SHP_XOR_PREV = 0x20 };

bool looks_like_shp(const uint8_t* raw, size_t len) {
    if (len < 20) {
        return false;
    }
    const uint16_t count = le16(raw);
    if (count == 0) {
        return false;
    }
    const size_t eof_pos = 14 + 8 * (size_t)count;
    if (eof_pos + 4 > len) {
        return false;
    }
    const uint32_t eof = le32(raw + eof_pos);
    return eof == len && (raw[17] == 0x20 || raw[17] == 0x40 || raw[17] == 0x80);
}

namespace {

struct ShpHeader {
    uint32_t offset = 0;
    uint8_t fmt = 0;
    uint16_t ref_offset = 0;
    uint16_t ref_fmt = 0;
    bool done = false;
};

struct ShpDecoder {
    const uint8_t* raw;
    size_t len;
    size_t size;
    std::vector<ShpHeader> headers;
    std::vector<std::vector<uint8_t>> data;
    std::string error;


    bool decode(size_t i, int depth) {
        if (headers[i].done) {
            return true;
        }
        if (depth > (int)headers.size()) {
            error = "SHP: zyklische Frame-Referenz";
            return false;
        }
        std::vector<uint8_t> buf;
        const ShpHeader& h = headers[i];
        if (h.fmt == SHP_LCW) {
            buf.assign(size, 0);
            if (lcw_decode(raw, len, h.offset, buf.data(), size) < 0) {
                error = "SHP: LCW-Daten defekt";
                return false;
            }
        } else if (h.fmt == SHP_XOR_PREV) {
            if (i == 0 || !decode(i - 1, depth + 1)) {
                if (error.empty()) {
                    error = "SHP: XOR-Vorgänger fehlt";
                }
                return false;
            }
            buf = data[i - 1];
            if (xor_delta_decode(raw, len, h.offset, buf.data(), size) < 0) {
                error = "SHP: XOR-Delta defekt";
                return false;
            }
        } else if (h.fmt == SHP_XOR_REF) {
            size_t ref = headers.size();
            for (size_t k = 0; k < headers.size(); ++k) {
                if (headers[k].offset == h.ref_offset) {
                    ref = k;
                    break;
                }
            }
            if (ref == headers.size() || !decode(ref, depth + 1)) {
                if (error.empty()) {
                    error = "SHP: Referenz zeigt auf keinen Frame";
                }
                return false;
            }
            buf = data[ref];
            if (xor_delta_decode(raw, len, h.offset, buf.data(), size) < 0) {
                error = "SHP: XOR-Delta defekt";
                return false;
            }
        } else {
            error = "SHP: unbekanntes Frameformat";
            return false;
        }
        data[i] = std::move(buf);
        headers[i].done = true;
        return true;
    }
};

}

bool load_shp(const uint8_t* raw, size_t len, FrameSet& out, std::string& error) {
    if (len < 14) {
        error = "SHP zu kurz";
        return false;
    }
    const uint16_t count = le16(raw);
    out.width = le16(raw + 6);
    out.height = le16(raw + 8);
    if (count == 0) {


        out.frames.clear();
        return true;
    }
    if (out.width <= 0 || out.height <= 0) {
        error = "SHP: ohne Maße";
        return false;
    }
    if (14 + (size_t)count * 8 > len) {
        error = "SHP: Frametabelle unvollständig";
        return false;
    }

    ShpDecoder dec;
    dec.raw = raw;
    dec.len = len;
    dec.size = (size_t)out.width * (size_t)out.height;
    dec.headers.resize(count);
    dec.data.resize(count);
    size_t pos = 14;
    for (uint16_t i = 0; i < count; ++i) {
        const uint32_t packed = le32(raw + pos);
        dec.headers[i].offset = packed & 0xFFFFFF;
        dec.headers[i].fmt = (uint8_t)(packed >> 24);
        dec.headers[i].ref_offset = le16(raw + pos + 4);
        dec.headers[i].ref_fmt = le16(raw + pos + 6);
        pos += 8;
    }

    for (uint16_t i = 0; i < count; ++i) {
        if (!dec.decode(i, 0)) {
            error = dec.error;
            return false;
        }
    }
    out.frames = std::move(dec.data);
    return true;
}

bool load_tmp(const uint8_t* raw, size_t len, FrameSet& out, std::string& error) {
    if (len < 40) {
        error = "TMP zu kurz";
        return false;
    }
    out.width = le16(raw);
    out.height = le16(raw + 2);
    const uint32_t img_start = le32(raw + 16);
    const int32_t index_end = (int32_t)le32(raw + 28);
    const int32_t index_start = (int32_t)le32(raw + 36);
    if (out.width <= 0 || out.height <= 0 || index_start < 0 || index_end < index_start ||
        (size_t)index_end > len) {
        error = "TMP: Index außerhalb der Datei";
        return false;
    }
    const size_t size = (size_t)out.width * (size_t)out.height;
    out.frames.clear();
    out.frames.reserve((size_t)(index_end - index_start));
    for (int32_t i = index_start; i < index_end; ++i) {
        const uint8_t b = raw[i];
        if (b == 255) {
            out.frames.emplace_back(size, 0);
            continue;
        }
        const size_t off = img_start + (size_t)b * size;
        std::vector<uint8_t> tile(size, 0);


        if (off < len) {
            std::memcpy(tile.data(), raw + off, off + size <= len ? size : len - off);
        }
        out.frames.push_back(std::move(tile));
    }
    return true;
}

bool load_frames(const uint8_t* raw, size_t len, const std::string& name, FrameSet& out, std::string& error) {
    const std::string ext = extension(name);
    if (ext == "shp" || looks_like_shp(raw, len)) {
        return load_shp(raw, len, out, error);
    }
    return load_tmp(raw, len, out, error);
}

bool palette_to_rgba(const uint8_t* raw, size_t len, std::vector<uint8_t>& out) {
    if (len < 768) {
        return false;
    }
    out.resize(1024);
    for (int i = 0; i < 256; ++i) {
        out[i * 4 + 0] = (uint8_t)(raw[i * 3 + 0] << 2);
        out[i * 4 + 1] = (uint8_t)(raw[i * 3 + 1] << 2);
        out[i * 4 + 2] = (uint8_t)(raw[i * 3 + 2] << 2);
        out[i * 4 + 3] = i == 0 ? 0 : 255;
    }
    return true;
}

}

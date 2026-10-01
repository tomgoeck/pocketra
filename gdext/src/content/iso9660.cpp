#include "iso9660.h"

#include <cstdio>
#include <cstring>

#include "platform.h"

namespace racontent {

namespace {

const size_t SECTOR = 2048;

inline uint32_t le32(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

bool read_sector(FILE* f, uint32_t lba, uint8_t* out, size_t count = 1) {
    if (std::fseek(f, (long)((size_t)lba * SECTOR), SEEK_SET) != 0) {
        return false;
    }
    return std::fread(out, 1, SECTOR * count, f) == SECTOR * count;
}

std::string trim_right(std::string s) {
    while (!s.empty() && (s.back() == ' ' || s.back() == '\0')) {
        s.pop_back();
    }
    return s;
}

}

void IsoImage::close() {
    if (file_) {
        std::fclose((FILE*)file_);
        file_ = nullptr;
    }
    entries_.clear();
    label_.clear();
}

bool IsoImage::open(const std::string& path, std::string& error) {
    close();
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) {
        error = "Abbild nicht lesbar: " + path;
        return false;
    }
    file_ = f;


    uint8_t sec[SECTOR];
    uint32_t root_lba = 0, root_size = 0;
    bool found = false;
    for (uint32_t s = 16; s < 32; ++s) {
        if (!read_sector(f, s, sec)) {
            break;
        }
        if (std::memcmp(sec + 1, "CD001", 5) != 0) {
            break;
        }
        if (sec[0] == 0xFF) {
            break;
        }
        if (sec[0] == 1) {
            label_ = trim_right(std::string((const char*)sec + 40, 32));

            const uint8_t* rec = sec + 156;
            root_lba = le32(rec + 2);
            root_size = le32(rec + 10);
            found = true;
            break;
        }
    }
    if (!found || root_size == 0) {
        error = "kein ISO-9660-Datenträger: " + path;
        close();
        return false;
    }
    read_dir(root_lba, root_size, "", 0);
    if (entries_.empty()) {
        error = "Abbild enthält keine Dateien";
        close();
        return false;
    }
    return true;
}

bool IsoImage::read_dir(uint32_t lba, uint32_t size, const std::string& prefix, int depth) {
    if (depth > 8 || size == 0) {
        return false;
    }
    FILE* f = (FILE*)file_;
    const size_t sectors = (size + SECTOR - 1) / SECTOR;
    std::vector<uint8_t> buf(sectors * SECTOR, 0);
    if (!read_sector(f, lba, buf.data(), sectors)) {
        return false;
    }

    struct Sub {
        uint32_t lba, size;
        std::string path;
    };
    std::vector<Sub> subdirs;

    size_t pos = 0;
    while (pos + 33 <= buf.size()) {
        const uint8_t rec_len = buf[pos];
        if (rec_len == 0) {

            const size_t next = ((pos / SECTOR) + 1) * SECTOR;
            if (next >= buf.size()) {
                break;
            }
            pos = next;
            continue;
        }
        if (pos + rec_len > buf.size()) {
            break;
        }
        const uint8_t* rec = buf.data() + pos;
        const uint32_t child_lba = le32(rec + 2);
        const uint32_t child_size = le32(rec + 10);
        const uint8_t flags = rec[25];
        const uint8_t name_len = rec[32];
        std::string name((const char*)rec + 33, name_len);
        pos += rec_len;

        if (name_len == 1 && (name[0] == '\0' || name[0] == '\1')) {
            continue;
        }
        const size_t semi = name.find(';');
        if (semi != std::string::npos) {
            name = name.substr(0, semi);
        }
        if (name.empty()) {
            continue;
        }
        const std::string full = prefix.empty() ? name : prefix + "/" + name;
        if (flags & 0x02) {
            subdirs.push_back({child_lba, child_size, full});
        } else {
            entries_.push_back({full, child_lba, child_size});
        }
    }

    for (const Sub& s : subdirs) {
        read_dir(s.lba, s.size, s.path, depth + 1);
    }
    return true;
}

const IsoEntry* IsoImage::find(const std::string& path) const {
    const std::string want = lower(path);
    for (const IsoEntry& e : entries_) {
        if (lower(e.path) == want) {
            return &e;
        }
    }

    for (const IsoEntry& e : entries_) {
        if (lower(base_name(e.path)) == want) {
            return &e;
        }
    }
    return nullptr;
}

bool IsoImage::extract(const IsoEntry& e, const std::string& out_path,
                       const std::function<void(float)>& progress, std::string& error) {
    FILE* f = (FILE*)file_;
    if (!f) {
        error = "Abbild nicht offen";
        return false;
    }
    const size_t slash = out_path.find_last_of('/');
    if (slash != std::string::npos) {
        make_dirs(out_path.substr(0, slash));
    }
    FILE* out = std::fopen(out_path.c_str(), "wb");
    if (!out) {
        error = "Ziel nicht schreibbar: " + out_path;
        return false;
    }
    if (std::fseek(f, (long)((size_t)e.lba * SECTOR), SEEK_SET) != 0) {
        std::fclose(out);
        error = "Abbild zu kurz";
        return false;
    }
    const size_t CHUNK = 1u << 20;
    std::vector<uint8_t> buf(CHUNK);
    size_t left = e.size;
    while (left > 0) {
        const size_t want = left < CHUNK ? left : CHUNK;
        if (std::fread(buf.data(), 1, want, f) != want) {
            std::fclose(out);
            error = "Abbild unvollständig";
            return false;
        }
        if (std::fwrite(buf.data(), 1, want, out) != want) {
            std::fclose(out);
            error = "Schreiben fehlgeschlagen";
            return false;
        }
        left -= want;
        if (progress) {
            progress(e.size ? 1.0f - (float)left / (float)e.size : 1.0f);
        }
    }
    std::fclose(out);
    return true;
}

bool IsoImage::read_all(const IsoEntry& e, std::vector<uint8_t>& out) const {
    FILE* f = (FILE*)file_;
    if (!f) {
        return false;
    }
    out.resize(e.size);
    if (e.size == 0) {
        return true;
    }
    if (std::fseek(f, (long)((size_t)e.lba * SECTOR), SEEK_SET) != 0) {
        return false;
    }
    return std::fread(out.data(), 1, out.size(), f) == out.size();
}

}

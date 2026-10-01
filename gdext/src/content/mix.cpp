#include "mix.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <set>

#include "blowfish.h"
#include "platform.h"

namespace racontent {


uint32_t classic_hash(const std::string& name) {
    std::string data;
    data.reserve(name.size() + 4);
    for (char c : name) {
        data.push_back((char)std::toupper((unsigned char)c));
    }
    while (data.size() % 4 != 0) {
        data.push_back('\0');
    }
    uint32_t result = 0;
    for (size_t i = 0; i < data.size(); i += 4) {
        const uint32_t word = (uint32_t)(uint8_t)data[i] | ((uint32_t)(uint8_t)data[i + 1] << 8) |
                              ((uint32_t)(uint8_t)data[i + 2] << 16) | ((uint32_t)(uint8_t)data[i + 3] << 24);
        result = ((result << 1) | (result >> 31)) + word;
    }
    return result;
}

bool NameDatabase::load(const std::string& path) {
    std::vector<uint8_t> data;
    if (!read_whole_file(path, data)) {
        return false;
    }
    return load_bytes(data.data(), data.size());
}

bool NameDatabase::load_bytes(const uint8_t* data, size_t len) {
    by_hash_.clear();
    size_t pos = 0;
    while (pos + 4 <= len) {
        int32_t count = 0;
        std::memcpy(&count, data + pos, 4);
        pos += 4;
        if (count <= 0) {
            break;
        }
        for (int32_t i = 0; i < count && pos < len; ++i) {
            const uint8_t* nul = (const uint8_t*)std::memchr(data + pos, 0, len - pos);
            if (!nul) {
                return !by_hash_.empty();
            }
            std::string name((const char*)(data + pos), (size_t)(nul - (data + pos)));
            pos = (size_t)(nul - data) + 1;

            if (pos >= len) {
                break;
            }
            const uint8_t* nul2 = (const uint8_t*)std::memchr(data + pos, 0, len - pos);
            if (!nul2) {
                break;
            }
            pos = (size_t)(nul2 - data) + 1;
            by_hash_.emplace(classic_hash(name), std::move(name));
        }
    }
    return !by_hash_.empty();
}

const std::string* NameDatabase::lookup(uint32_t hash) const {
    auto it = by_hash_.find(hash);
    return it == by_hash_.end() ? nullptr : &it->second;
}


FileSource::~FileSource() {
    if (f_) {
        std::fclose(f_);
    }
}

std::shared_ptr<FileSource> FileSource::open(const std::string& path) {
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) {
        return nullptr;
    }
    auto s = std::shared_ptr<FileSource>(new FileSource());
    s->f_ = f;
    s->path_ = path;
    std::fseek(f, 0, SEEK_END);
    s->size_ = std::ftell(f);
    std::fseek(f, 0, SEEK_SET);
    return s;
}

bool FileSource::read_at(long offset, size_t len, uint8_t* out) const {
    if (offset < 0 || (long)(offset + (long)len) > size_) {
        return false;
    }
    if (std::fseek(f_, offset, SEEK_SET) != 0) {
        return false;
    }
    return std::fread(out, 1, len, f_) == len;
}


static inline uint16_t le16(const uint8_t* p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static inline uint32_t le32(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

bool MixArchive::parse(std::shared_ptr<FileSource> src, long base, long limit, const NameDatabase* names,
                       std::string& error) {
    src_ = std::move(src);
    entries_.clear();
    by_hash_.clear();
    if (limit - base < 8) {
        error = "Archiv zu kurz";
        return false;
    }

    uint8_t head[92];
    if (!src_->read_at(base, 92 > (size_t)(limit - base) ? (size_t)(limit - base) : 92, head)) {
        error = "Kopf nicht lesbar";
        return false;
    }

    std::vector<uint8_t> header;
    size_t header_pos = 0;
    long data_start = 0;

    td_format_ = le16(head) != 0;
    encrypted_ = false;
    if (td_format_) {

        header.resize(6);
        if (!src_->read_at(base, 6, header.data())) {
            error = "Kopf nicht lesbar";
            return false;
        }
        header_pos = 0;
    } else {
        const uint16_t flags = le16(head + 2);
        encrypted_ = (flags & 0x2) != 0;
        if (!encrypted_) {
            header.resize(10);
            if (!src_->read_at(base, 10, header.data())) {
                error = "Kopf nicht lesbar";
                return false;
            }
            header_pos = 4;
        }
    }

    uint16_t num_files = 0;
    if (encrypted_) {
        if (limit - base < 92) {
            error = "verschlüsselter Kopf zu kurz";
            return false;
        }
        std::vector<uint8_t> keyblock(80);
        if (!src_->read_at(base + 4, 80, keyblock.data())) {
            error = "Schlüsselblock nicht lesbar";
            return false;
        }
        std::vector<uint8_t> key = decrypt_blowfish_key(keyblock.data(), keyblock.size());
        if (key.empty()) {
            error = "Blowfish-Schlüssel nicht ableitbar";
            return false;
        }
        Blowfish fish(key.data(), key.size());
        uint8_t first[8];
        if (!src_->read_at(base + 84, 8, first)) {
            error = "Kopfblock nicht lesbar";
            return false;
        }
        fish.decrypt(first, 8);
        num_files = le16(first);
        const size_t block_count = (13 + (size_t)num_files * 12) / 8;
        header.resize(block_count * 8);
        if (block_count * 8 > (size_t)(limit - base - 84)) {
            error = "Kopf reicht über das Archivende hinaus";
            return false;
        }
        if (!src_->read_at(base + 84, block_count * 8, header.data())) {
            error = "Kopf nicht lesbar";
            return false;
        }
        fish.decrypt(header.data(), header.size());
        header_pos = 0;
        data_start = base + 84 + (long)(block_count * 8);
    } else {
        num_files = le16(header.data() + header_pos);
        const long header_len_prefix = td_format_ ? 0 : 4;
        data_start = base + header_len_prefix + 6 + (long)num_files * 12;

        header.resize(header_pos + 6 + (size_t)num_files * 12);
        if ((long)header.size() > limit - base) {
            error = "Kopf reicht über das Archivende hinaus";
            return false;
        }
        if (!src_->read_at(base, header.size(), header.data())) {
            error = "Eintragstabelle nicht lesbar";
            return false;
        }
    }

    entries_.reserve(num_files);
    size_t pos = header_pos + 6;
    for (uint16_t i = 0; i < num_files; ++i) {
        if (pos + 12 > header.size()) {
            error = "Eintragstabelle unvollständig";
            return false;
        }
        MixEntry e;
        e.hash = le32(header.data() + pos);
        const uint32_t off = le32(header.data() + pos + 4);
        e.length = le32(header.data() + pos + 8);
        pos += 12;
        e.offset = data_start + (long)off;
        if (names) {
            const std::string* n = names->lookup(e.hash);
            if (n) {
                e.name = *n;
            }
        }
        by_hash_.emplace(e.hash, entries_.size());
        entries_.push_back(std::move(e));
    }
    return true;
}

const MixEntry* MixArchive::entry(const std::string& name) const {
    auto it = by_hash_.find(classic_hash(name));
    if (it == by_hash_.end()) {
        return nullptr;
    }
    return &entries_[it->second];
}

bool MixArchive::read(const MixEntry& e, std::vector<uint8_t>& out) const {
    out.resize(e.length);
    if (e.length == 0) {
        return true;
    }
    return src_ && src_->read_at(e.offset, e.length, out.data());
}

size_t MixArchive::named() const {
    size_t n = 0;
    for (const auto& e : entries_) {
        if (!e.name.empty()) {
            ++n;
        }
    }
    return n;
}


static std::string to_lower(std::string s) {
    for (char& c : s) {
        c = (char)std::tolower((unsigned char)c);
    }
    return s;
}

void ContentSet::clear() { mixes_.clear(); }

bool ContentSet::add_file(const std::string& path, std::string& error) {
    auto src = FileSource::open(path);
    if (!src) {
        error = "Datei nicht lesbar: " + path;
        return false;
    }
    auto mix = std::unique_ptr<MixArchive>(new MixArchive());
    if (!mix->parse(src, 0, src->size(), names_.get(), error)) {
        return false;
    }
    mix->set_label(base_name(path));
    MixArchive* raw = mix.get();
    mixes_.push_back(std::move(mix));
    add_nested(*raw);
    return true;
}

void ContentSet::add_nested(MixArchive& mix) {

    std::vector<MixEntry> entries = mix.entries();
    const std::string parent = mix.label();
    auto src = mix.source();
    for (const MixEntry& e : entries) {
        if (e.name.empty()) {
            continue;
        }
        const std::string lower = to_lower(e.name);
        if (lower.size() < 4 || lower.compare(lower.size() - 4, 4, ".mix") != 0) {
            continue;
        }
        auto inner = std::unique_ptr<MixArchive>(new MixArchive());
        std::string err;
        if (!inner->parse(src, e.offset, e.offset + (long)e.length, names_.get(), err)) {
            continue;
        }
        inner->set_label(parent + "/" + e.name);
        MixArchive* raw = inner.get();
        mixes_.push_back(std::move(inner));
        add_nested(*raw);
    }
}

int ContentSet::add_dir(const std::string& dir, std::string& error) {
    std::vector<std::string> paths;
    list_files_recursive(dir, paths);
    std::vector<std::string> mixes;
    for (const std::string& p : paths) {
        const std::string lower = to_lower(p);
        if (lower.size() >= 4 && lower.compare(lower.size() - 4, 4, ".mix") == 0) {
            mixes.push_back(p);
        }
    }

    std::sort(mixes.begin(), mixes.end(),
              [](const std::string& a, const std::string& b) { return to_lower(a) < to_lower(b); });
    int n = 0;
    for (const std::string& p : mixes) {
        std::string err;
        if (add_file(p, err)) {
            ++n;
        } else if (error.empty()) {
            error = err;
        }
    }
    if (n > 0) {
        error.clear();
    } else if (error.empty()) {
        error = "keine MIX-Archive unter " + dir;
    }
    return n;
}

bool ContentSet::has(const std::string& name) const {
    for (const auto& m : mixes_) {
        if (m->entry(name)) {
            return true;
        }
    }
    return false;
}

bool ContentSet::read(const std::string& name, std::vector<uint8_t>& out) const {
    for (const auto& m : mixes_) {
        const MixEntry* e = m->entry(name);
        if (e) {
            return m->read(*e, out);
        }
    }
    return false;
}

std::vector<std::string> ContentSet::list() const {
    std::set<std::string> names;
    for (const auto& m : mixes_) {
        for (const auto& e : m->entries()) {
            if (!e.name.empty()) {
                names.insert(e.name);
            }
        }
    }
    return std::vector<std::string>(names.begin(), names.end());
}

}

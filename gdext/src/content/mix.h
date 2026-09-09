

#pragma once

#include <cstdint>
#include <cstdio>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace racontent {


uint32_t classic_hash(const std::string& name);


class NameDatabase {
public:
    bool load(const std::string& path);
    bool load_bytes(const uint8_t* data, size_t len);
    const std::string* lookup(uint32_t hash) const;
    size_t size() const { return by_hash_.size(); }

private:
    std::unordered_map<uint32_t, std::string> by_hash_;
};


class FileSource {
public:
    ~FileSource();
    static std::shared_ptr<FileSource> open(const std::string& path);
    bool read_at(long offset, size_t len, uint8_t* out) const;
    long size() const { return size_; }
    const std::string& path() const { return path_; }

private:
    FILE* f_ = nullptr;
    long size_ = 0;
    std::string path_;
};

struct MixEntry {
    uint32_t hash = 0;
    long offset = 0;
    uint32_t length = 0;
    std::string name;
};

class MixArchive {
public:


    bool parse(std::shared_ptr<FileSource> src, long base, long limit, const NameDatabase* names,
               std::string& error);

    const MixEntry* entry(const std::string& name) const;
    bool read(const MixEntry& e, std::vector<uint8_t>& out) const;
    const std::vector<MixEntry>& entries() const { return entries_; }
    const std::string& label() const { return label_; }
    void set_label(std::string l) { label_ = std::move(l); }
    bool encrypted() const { return encrypted_; }
    bool td_format() const { return td_format_; }
    size_t named() const;
    const std::shared_ptr<FileSource>& source() const { return src_; }

private:
    std::shared_ptr<FileSource> src_;
    std::vector<MixEntry> entries_;
    std::unordered_map<uint32_t, size_t> by_hash_;
    std::string label_;
    bool encrypted_ = false;
    bool td_format_ = false;
};


class ContentSet {
public:

    bool add_file(const std::string& path, std::string& error);

    int add_dir(const std::string& dir, std::string& error);
    void clear();

    void set_names(std::shared_ptr<NameDatabase> n) { names_ = std::move(n); }
    const NameDatabase* names() const { return names_.get(); }

    bool has(const std::string& name) const;
    bool read(const std::string& name, std::vector<uint8_t>& out) const;

    std::vector<std::string> list() const;
    const std::vector<std::unique_ptr<MixArchive>>& archives() const { return mixes_; }

private:
    void add_nested(MixArchive& mix);

    std::vector<std::unique_ptr<MixArchive>> mixes_;
    std::shared_ptr<NameDatabase> names_;
};

}



#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace racontent {

struct IsoEntry {
    std::string path;
    uint32_t lba = 0;
    uint32_t size = 0;
};

class IsoImage {
public:
    bool open(const std::string& path, std::string& error);
    void close();

    const std::vector<IsoEntry>& entries() const { return entries_; }
    const std::string& label() const { return label_; }
    const IsoEntry* find(const std::string& path) const;


    bool extract(const IsoEntry& e, const std::string& out_path,
                 const std::function<void(float)>& progress, std::string& error);
    bool read_all(const IsoEntry& e, std::vector<uint8_t>& out) const;

private:
    bool read_dir(uint32_t lba, uint32_t size, const std::string& prefix, int depth);

    void* file_ = nullptr;
    std::vector<IsoEntry> entries_;
    std::string label_;
};

}

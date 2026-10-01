

#pragma once

#include <functional>
#include <string>
#include <vector>

#include "mix.h"
#include "sprites.h"

namespace racontent {


using ProgressFn = std::function<void(const char*, float, const std::string&)>;


using AssetFn = std::function<bool(const std::string& path, std::vector<uint8_t>& out)>;


constexpr int WEB_PAGE = 2048;


constexpr int WEB_MAX_PAGES = 6;


struct WebPlacement {
    int page = 0;
    int x = 0;
    int y = 0;
};

struct AtlasRecipe {
    int format = 0;
    std::string tileset;
    std::string palette;
    int max_width = 4096;
    std::vector<std::string> bits_first;
    std::vector<std::pair<std::string, std::string>> sprites;
    std::string meta;

    bool load_bytes(const uint8_t* data, size_t len, const std::string& label, std::string& error);
};

class AtlasBuilder {
public:
    void set_recipe_dir(std::string d) { recipe_dir_ = std::move(d); }
    void set_bits_dir(std::string d) { bits_dir_ = std::move(d); }
    void set_asset_reader(AssetFn f) { read_asset_ = std::move(f); }


    void set_web_pages(bool on) { web_pages_ = on; }


    bool build(const ContentSet& cs, const std::vector<std::string>& tilesets, const std::string& out_dir,
               const ProgressFn& progress, std::string& error);


    bool build_one(const ContentSet& cs, const std::string& tileset, const std::string& out_dir,
                   const ProgressFn& progress, float base, float span, std::string& error);

    const std::vector<std::string>& missing() const { return missing_; }

private:


    bool read_source(const ContentSet& cs, const AtlasRecipe& r, const std::string& filename,
                     std::vector<uint8_t>& out) const;

    bool build_volkicon(const ContentSet& cs, FrameSet& out) const;

    bool read_asset(const std::string& path, std::vector<uint8_t>& out) const;

    AssetFn read_asset_;
    std::string recipe_dir_ = "data/atlas";
    std::string bits_dir_ = "data/bits";
    std::vector<std::string> missing_;
    bool web_pages_ = false;
};


void shelf_pack(const std::vector<std::pair<int, int>>& items, int max_width, int& out_width,
                int& out_height, std::vector<std::pair<int, int>>& out_pos);


int web_shelf_pack(const std::vector<std::pair<int, int>>& items, std::vector<WebPlacement>& out_pos);

}

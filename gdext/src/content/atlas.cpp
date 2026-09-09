#include "atlas.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <numeric>
#include <sstream>

#include "platform.h"

namespace racontent {


bool AtlasRecipe::load_bytes(const uint8_t* data, size_t len, const std::string& label,
                             std::string& error) {
    std::string text((const char*)data, len);
    std::istringstream in(text);
    std::string line;
    bool has_meta = false;
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        if (line.empty()) {
            continue;
        }
        const size_t sp = line.find(' ');
        const std::string key = line.substr(0, sp);
        const std::string rest = sp == std::string::npos ? std::string() : line.substr(sp + 1);
        if (key == "format") {
            format = std::atoi(rest.c_str());
        } else if (key == "tileset") {
            tileset = rest;
        } else if (key == "palette") {
            palette = rest;
        } else if (key == "max_width") {
            max_width = std::atoi(rest.c_str());
        } else if (key == "bits_first") {
            std::istringstream ss(rest);
            std::string tok;
            while (ss >> tok) {
                bits_first.push_back(lower(tok));
            }
        } else if (key == "sprite") {
            const size_t sp2 = rest.find(' ');
            if (sp2 == std::string::npos) {
                continue;
            }
            sprites.emplace_back(rest.substr(0, sp2), rest.substr(sp2 + 1));
        } else if (key == "meta") {
            meta = rest;
            has_meta = true;
        }
    }
    if (format != 1 || sprites.empty() || !has_meta) {
        error = "Rezept unbrauchbar: " + label;
        return false;
    }
    return true;
}


void shelf_pack(const std::vector<std::pair<int, int>>& items, int max_width, int& out_width,
                int& out_height, std::vector<std::pair<int, int>>& out_pos) {
    std::vector<size_t> order(items.size());
    std::iota(order.begin(), order.end(), 0);

    std::stable_sort(order.begin(), order.end(), [&items](size_t a, size_t b) {
        if (items[a].second != items[b].second) {
            return items[a].second > items[b].second;
        }
        return items[a].first > items[b].first;
    });
    out_pos.assign(items.size(), {0, 0});
    int x = 0, y = 0, shelf_h = 0, width = 0;
    for (size_t i : order) {
        const int w = items[i].first, h = items[i].second;
        if (x + w > max_width) {
            y += shelf_h;
            x = 0;
            shelf_h = 0;
        }
        out_pos[i] = {x, y};
        x += w;
        shelf_h = std::max(shelf_h, h);
        width = std::max(width, x);
    }
    out_width = width;
    out_height = y + shelf_h;
}


bool AtlasBuilder::read_asset(const std::string& path, std::vector<uint8_t>& out) const {
    if (read_asset_) {
        return read_asset_(path, out);
    }
    return read_whole_file(path, out);
}

bool AtlasBuilder::read_source(const ContentSet& cs, const AtlasRecipe& r, const std::string& filename,
                               std::vector<uint8_t>& out) const {
    const std::string low = lower(filename);
    const std::string bits_path = join_path(bits_dir_, low);


    if (std::find(r.bits_first.begin(), r.bits_first.end(), low) != r.bits_first.end() &&
        read_asset(bits_path, out)) {
        return true;
    }
    if (cs.read(filename, out)) {
        return true;
    }
    return read_asset(bits_path, out);
}

bool AtlasBuilder::build_volkicon(const ContentSet& cs, FrameSet& out) const {


    const int W = 64, H = 48;
    std::vector<uint8_t> plate;
    if (!read_asset(join_path(bits_dir_, "volkicon.plate"), plate) || plate.size() != (size_t)(W * H)) {
        return false;
    }
    std::vector<uint8_t> raw;
    if (!cs.read("gnrl.shp", raw)) {
        return false;
    }
    FrameSet src;
    std::string err;
    if (!load_shp(raw.data(), raw.size(), src, err) || src.frames.empty()) {
        return false;
    }
    const int cx0 = 19, cy0 = 3, cx1 = 30, cy1 = 21, scale = 2;
    const int char_w = (cx1 - cx0) * scale, char_h = (cy1 - cy0) * scale;
    const int ox = (W - char_w) / 2, oy = 1;
    std::vector<uint8_t> frame = plate;
    for (int y = 0; y < char_h; ++y) {
        for (int x = 0; x < char_w; ++x) {
            const int sx = cx0 + x / scale;
            const int sy = cy0 + y / scale;
            if (sx >= src.width || sy >= src.height) {
                continue;
            }
            const uint8_t si = src.frames[0][(size_t)sy * src.width + sx];
            if (si == 0 || si == 4) {
                continue;
            }
            frame[(size_t)(oy + y) * W + (ox + x)] = si;
        }
    }
    out.width = W;
    out.height = H;
    out.frames.clear();
    out.frames.push_back(std::move(frame));
    return true;
}

bool AtlasBuilder::build_one(const ContentSet& cs, const std::string& tileset, const std::string& out_dir,
                             const ProgressFn& progress, float base, float span, std::string& error) {
    AtlasRecipe r;
    const std::string recipe_path = join_path(recipe_dir_, tileset + ".recipe");
    std::vector<uint8_t> recipe_raw;
    if (!read_asset(recipe_path, recipe_raw)) {
        error = "Rezept fehlt: " + recipe_path;
        return false;
    }
    if (!r.load_bytes(recipe_raw.data(), recipe_raw.size(), recipe_path, error)) {
        return false;
    }

    std::vector<std::string> stems;
    std::vector<FrameSet> sets;
    stems.reserve(r.sprites.size());
    sets.reserve(r.sprites.size());

    const size_t total = r.sprites.size();
    for (size_t i = 0; i < total; ++i) {
        const std::string& sprite_stem = r.sprites[i].first;
        const std::string& file = r.sprites[i].second;
        if (progress && (i % 32 == 0)) {
            progress("atlas", base + span * 0.7f * (float)i / (float)total, tileset + ": " + sprite_stem);
        }
        FrameSet fs;
        std::string err;
        std::vector<uint8_t> raw;
        if (!read_source(cs, r, file, raw)) {

            if (sprite_stem != "volkicon" || !build_volkicon(cs, fs)) {
                missing_.push_back(file);
                continue;
            }
        } else if (!load_frames(raw.data(), raw.size(), file, fs, err)) {
            missing_.push_back(file + " (" + err + ")");
            continue;
        }
        stems.push_back(sprite_stem);
        sets.push_back(std::move(fs));
    }
    if (sets.empty()) {
        error = "kein einziges Sprite für " + tileset + " lesbar";
        return false;
    }

    std::vector<std::pair<int, int>> items;
    for (const FrameSet& s : sets) {
        for (size_t k = 0; k < s.frames.size(); ++k) {
            items.emplace_back(s.width, s.height);
        }
    }
    int width = 0, height = 0;
    std::vector<std::pair<int, int>> pos;
    shelf_pack(items, r.max_width, width, height, pos);
    if (width <= 0 || height <= 0) {
        error = "Atlas leer";
        return false;
    }

    if (progress) {
        progress("atlas", base + span * 0.75f, tileset + ": packen");
    }
    std::vector<uint8_t> atlas((size_t)width * (size_t)height, 0);
    std::string json;
    json.reserve(1 << 20);
    json += "{\"width\":";
    json += std::to_string(width);
    json += ",\"height\":";
    json += std::to_string(height);
    json += ",\"frames\":[";

    size_t k = 0;
    bool first = true;
    char buf[256];
    for (size_t si = 0; si < sets.size(); ++si) {
        const FrameSet& s = sets[si];
        for (size_t fi = 0; fi < s.frames.size(); ++fi, ++k) {
            const int x = pos[k].first, y = pos[k].second;
            const std::vector<uint8_t>& f = s.frames[fi];
            for (int row = 0; row < s.height; ++row) {
                const size_t dst = (size_t)(y + row) * width + x;
                const size_t src = (size_t)row * s.width;
                if (src + s.width <= f.size()) {
                    std::memcpy(atlas.data() + dst, f.data() + src, (size_t)s.width);
                }
            }
            if (!first) {
                json += ',';
            }
            first = false;
            std::snprintf(buf, sizeof(buf), "{\"sprite\":\"%s\",\"frame\":%zu,\"x\":%d,\"y\":%d,\"w\":%d,\"h\":%d}",
                          stems[si].c_str(), fi, x, y, s.width, s.height);
            json += buf;
        }
    }
    json += "]";
    if (!r.meta.empty()) {
        json += ',';
        json += r.meta;
    }
    json += '}';

    make_dirs(out_dir);
    const std::string name = "atlas_" + tileset;
    if (!write_whole_file(join_path(out_dir, name + ".r8"), atlas.data(), atlas.size())) {
        error = "Atlas nicht schreibbar: " + out_dir;
        return false;
    }
    if (!write_whole_file(join_path(out_dir, name + ".json"), (const uint8_t*)json.data(), json.size())) {
        error = "Atlasdaten nicht schreibbar: " + out_dir;
        return false;
    }

    std::vector<uint8_t> pal_raw, rgba;
    if (!read_source(cs, r, r.palette, pal_raw) || !palette_to_rgba(pal_raw.data(), pal_raw.size(), rgba)) {
        error = "Palette fehlt: " + r.palette;
        return false;
    }
    if (!write_whole_file(join_path(out_dir, stem(r.palette) + ".rgba"), rgba.data(), rgba.size())) {
        error = "Palette nicht schreibbar";
        return false;
    }
    if (progress) {
        progress("atlas", base + span, tileset);
    }
    return true;
}

bool AtlasBuilder::build(const ContentSet& cs, const std::vector<std::string>& tilesets,
                         const std::string& out_dir, const ProgressFn& progress, std::string& error) {
    missing_.clear();
    if (tilesets.empty()) {
        error = "keine Tilesets angegeben";
        return false;
    }
    const float span = 1.0f / (float)tilesets.size();
    for (size_t i = 0; i < tilesets.size(); ++i) {
        if (!build_one(cs, tilesets[i], out_dir, progress, span * (float)i, span, error)) {
            return false;
        }
    }
    return true;
}

}

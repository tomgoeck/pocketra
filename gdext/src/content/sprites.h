

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace racontent {


bool looks_like_shp(const uint8_t* raw, size_t len);


struct FrameSet {
    int width = 0;
    int height = 0;
    std::vector<std::vector<uint8_t>> frames;
    size_t size() const { return frames.size(); }
};


bool load_shp(const uint8_t* raw, size_t len, FrameSet& out, std::string& error);


bool load_tmp(const uint8_t* raw, size_t len, FrameSet& out, std::string& error);


bool load_frames(const uint8_t* raw, size_t len, const std::string& name, FrameSet& out, std::string& error);


bool palette_to_rgba(const uint8_t* raw, size_t len, std::vector<uint8_t>& out);

}

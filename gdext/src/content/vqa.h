

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace racontent {

class VqaDecoder {
public:
    bool open(std::vector<uint8_t> data, std::string& error);

    int width() const { return width_; }
    int height() const { return height_; }
    int frame_count() const { return frame_count_; }
    int fps() const { return framerate_ ? framerate_ : 15; }
    double length_seconds() const { return frame_count_ / (double)fps(); }

    int audio_rate() const { return audio_rate_; }
    int audio_channels() const { return audio_channels_; }

    void take_audio(std::vector<uint8_t>& out) { out = audio_; }
    const std::vector<uint8_t>& audio() const { return audio_; }


    bool seek(int frame, std::string& error);

    bool next_frame(std::string& error);
    int current_frame() const { return current_; }


    const std::vector<uint8_t>& frame_indices() const { return frame_; }

    const std::vector<uint8_t>& palette() const { return palette_; }

    void frame_rgba(std::vector<uint8_t>& out) const;

private:
    bool parse_header(std::string& error);
    bool collect_audio(std::string& error);
    bool load_frame(int index, std::string& error);
    bool decode_vqfr(size_t& pos, size_t end, bool is_vqfl, std::string& error);
    void decode_frame_data();

    std::vector<uint8_t> data_;
    int width_ = 0, height_ = 0;
    int frame_count_ = 0;
    int framerate_ = 15;
    int block_w_ = 4, block_h_ = 2;
    int blocks_x_ = 0, blocks_y_ = 0;
    int num_colors_ = 256;
    int chunk_buffer_parts_ = 0;
    uint32_t video_flags_ = 0;
    int audio_rate_ = 22050, audio_channels_ = 1, audio_bits_ = 16;
    std::vector<uint32_t> offsets_;

    std::vector<uint8_t> cbf_, cbp_, cbf_buffer_, orig_;
    int current_chunk_buffer_ = 0;
    size_t chunk_buffer_offset_ = 0;
    bool cbp_compressed_ = false;

    std::vector<uint8_t> palette_;
    std::vector<uint8_t> frame_;
    std::vector<uint8_t> audio_;
    int current_ = -1;
};

}



#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace racontent {

struct AudClip {
    int sample_rate = 22050;
    int channels = 1;
    int bits = 16;
    std::vector<uint8_t> pcm;

    size_t frame_count() const {
        const int bytes = (bits / 8) * channels;
        return bytes > 0 ? pcm.size() / (size_t)bytes : 0;
    }
    double length_seconds() const {
        return sample_rate > 0 ? (double)frame_count() / sample_rate : 0.0;
    }
};


bool aud_probe(const uint8_t* raw, size_t len, int& sample_rate, int& channels, int& bits,
               int& format, uint32_t& output_size);

bool decode_aud(const uint8_t* raw, size_t len, AudClip& out, std::string& error);


void pcm_to_wav(const AudClip& clip, std::vector<uint8_t>& out);


class AudStreamDecoder {
public:
    bool open(std::vector<uint8_t> data, std::string& error);
    void rewind();

    bool next_block(std::vector<uint8_t>& out);
    int sample_rate() const { return sample_rate_; }
    int channels() const { return channels_; }
    int bits() const { return bits_; }
    double length_seconds() const;

private:
    std::vector<uint8_t> data_;
    size_t pos_ = 0;
    size_t first_ = 0;
    int sample_rate_ = 22050;
    int channels_ = 1;
    int bits_ = 16;
    int format_ = 99;
    uint32_t output_size_ = 0;

    int index_ = 0;
    int current_ = 0;
    uint32_t written_ = 0;
};

}

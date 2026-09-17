

#pragma once

#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback_resampled.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <memory>
#include <vector>

#include "../aud.h"

namespace godot {

class AudStream : public AudioStream {
    GDCLASS(AudStream, AudioStream)

public:
    static Ref<AudStream> load_from_buffer(const PackedByteArray& data);
    static Ref<AudStream> load_from_file(const String& path);

    bool set_data(std::vector<uint8_t> data);

    int sample_rate() const { return sample_rate_; }
    int channels() const { return channels_; }
    void set_loop(bool on) { loop_ = on; }
    bool is_loop() const { return loop_; }
    const std::vector<uint8_t>& raw() const { return raw_; }

    Ref<AudioStreamPlayback> _instantiate_playback() const override;
    double _get_length() const override;
    String _get_stream_name() const override;

protected:
    static void _bind_methods();

private:
    std::vector<uint8_t> raw_;
    int sample_rate_ = 22050;
    int channels_ = 1;
    double length_ = 0.0;
    bool loop_ = false;
};

class AudStreamPlayback : public AudioStreamPlaybackResampled {
    GDCLASS(AudStreamPlayback, AudioStreamPlaybackResampled)

public:
    void setup(const Ref<AudStream>& stream);

    void _start(double from_pos) override;
    void _stop() override;
    bool _is_playing() const override;
    int32_t _get_loop_count() const override;
    double _get_playback_position() const override;
    void _seek(double position) override;
    int32_t _mix_resampled(AudioFrame* dst, int32_t frames) override;
    float _get_stream_sampling_rate() const override;

protected:
    static void _bind_methods() {}

private:
    bool fill();

    Ref<AudStream> stream_;
    racontent::AudStreamDecoder decoder_;
    std::vector<uint8_t> block_;
    size_t block_pos_ = 0;
    bool active_ = false;
    int32_t loops_ = 0;
    int64_t frames_played_ = 0;
};

}

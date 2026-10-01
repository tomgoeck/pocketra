#include "aud_stream.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {


void AudStream::_bind_methods() {
    ClassDB::bind_static_method("AudStream", D_METHOD("load_from_buffer", "data"),
                                &AudStream::load_from_buffer);
    ClassDB::bind_static_method("AudStream", D_METHOD("load_from_file", "path"), &AudStream::load_from_file);
    ClassDB::bind_method(D_METHOD("sample_rate"), &AudStream::sample_rate);
    ClassDB::bind_method(D_METHOD("channels"), &AudStream::channels);
    ClassDB::bind_method(D_METHOD("set_loop", "on"), &AudStream::set_loop);
    ClassDB::bind_method(D_METHOD("is_loop"), &AudStream::is_loop);
}

bool AudStream::set_data(std::vector<uint8_t> data) {
    racontent::AudStreamDecoder probe;
    std::string err;
    if (!probe.open(data, err)) {
        return false;
    }
    sample_rate_ = probe.sample_rate();
    channels_ = probe.channels();
    length_ = probe.length_seconds();
    raw_ = std::move(data);
    return true;
}

Ref<AudStream> AudStream::load_from_buffer(const PackedByteArray& data) {
    Ref<AudStream> s;
    s.instantiate();
    std::vector<uint8_t> buf((const uint8_t*)data.ptr(), (const uint8_t*)data.ptr() + data.size());
    if (!s->set_data(std::move(buf))) {
        return Ref<AudStream>();
    }
    return s;
}

Ref<AudStream> AudStream::load_from_file(const String& path) {
    const PackedByteArray data = FileAccess::get_file_as_bytes(path);
    if (data.is_empty()) {
        return Ref<AudStream>();
    }
    return load_from_buffer(data);
}

Ref<AudioStreamPlayback> AudStream::_instantiate_playback() const {
    Ref<AudStreamPlayback> pb;
    pb.instantiate();
    pb->setup(Ref<AudStream>(const_cast<AudStream*>(this)));
    return pb;
}

double AudStream::_get_length() const { return length_; }

String AudStream::_get_stream_name() const { return "AUD"; }


void AudStreamPlayback::setup(const Ref<AudStream>& stream) {
    stream_ = stream;
    if (stream_.is_valid()) {
        std::string err;
        decoder_.open(stream_->raw(), err);
    }
}

void AudStreamPlayback::_start(double from_pos) {
    active_ = true;
    loops_ = 0;
    frames_played_ = 0;
    block_.clear();
    block_pos_ = 0;
    decoder_.rewind();
    begin_resample();
    if (from_pos > 0.0) {
        _seek(from_pos);
    }
}

void AudStreamPlayback::_stop() { active_ = false; }

bool AudStreamPlayback::_is_playing() const { return active_; }

int32_t AudStreamPlayback::_get_loop_count() const { return loops_; }

double AudStreamPlayback::_get_playback_position() const {
    const int rate = decoder_.sample_rate() > 0 ? decoder_.sample_rate() : 22050;
    return (double)frames_played_ / (double)rate;
}

void AudStreamPlayback::_seek(double position) {

    decoder_.rewind();
    block_.clear();
    block_pos_ = 0;
    frames_played_ = 0;
    if (position <= 0.0) {
        return;
    }
    const int rate = decoder_.sample_rate() > 0 ? decoder_.sample_rate() : 22050;
    const int64_t want = (int64_t)(position * rate);
    const int bytes_per_frame = (decoder_.bits() / 8) * decoder_.channels();
    while (frames_played_ < want) {
        if (!fill()) {
            break;
        }
        const int64_t have = (int64_t)(block_.size() / (size_t)bytes_per_frame);
        if (frames_played_ + have <= want) {
            frames_played_ += have;
            block_.clear();
            block_pos_ = 0;
        } else {
            block_pos_ = (size_t)((want - frames_played_) * bytes_per_frame);
            frames_played_ = want;
        }
    }
}

bool AudStreamPlayback::fill() {
    block_pos_ = 0;
    if (decoder_.next_block(block_)) {
        return true;
    }
    if (stream_.is_valid() && stream_->is_loop()) {
        ++loops_;
        decoder_.rewind();
        frames_played_ = 0;
        return decoder_.next_block(block_);
    }
    return false;
}

float AudStreamPlayback::_get_stream_sampling_rate() const {
    return (float)(decoder_.sample_rate() > 0 ? decoder_.sample_rate() : 22050);
}

int32_t AudStreamPlayback::_mix_resampled(AudioFrame* dst, int32_t frames) {
    if (!active_ || !dst) {
        return 0;
    }
    const int bits = decoder_.bits();
    const int channels = decoder_.channels();
    const int bytes_per_frame = (bits / 8) * channels;
    int32_t written = 0;
    while (written < frames) {
        if (block_pos_ + (size_t)bytes_per_frame > block_.size()) {
            if (!fill()) {
                break;
            }
            if (block_.empty()) {
                break;
            }
        }
        float l = 0.0f, r = 0.0f;
        if (bits == 16) {
            const int16_t s0 = (int16_t)((uint16_t)block_[block_pos_] |
                                         ((uint16_t)block_[block_pos_ + 1] << 8));
            l = (float)s0 / 32768.0f;
            r = l;
            if (channels == 2) {
                const int16_t s1 = (int16_t)((uint16_t)block_[block_pos_ + 2] |
                                             ((uint16_t)block_[block_pos_ + 3] << 8));
                r = (float)s1 / 32768.0f;
            }
        } else {
            l = ((float)block_[block_pos_] - 128.0f) / 128.0f;
            r = l;
            if (channels == 2) {
                r = ((float)block_[block_pos_ + 1] - 128.0f) / 128.0f;
            }
        }
        block_pos_ += (size_t)bytes_per_frame;
        dst[written].left = l;
        dst[written].right = r;
        ++written;
        ++frames_played_;
    }
    if (written < frames) {
        active_ = false;
        for (int32_t i = written; i < frames; ++i) {
            dst[i].left = 0.0f;
            dst[i].right = 0.0f;
        }
    }
    return frames;
}

}

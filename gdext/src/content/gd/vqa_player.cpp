#include "vqa_player.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {

void VqaPlayer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("open_buffer", "data"), &VqaPlayer::open_buffer);
    ClassDB::bind_method(D_METHOD("open_file", "path"), &VqaPlayer::open_file);
    ClassDB::bind_method(D_METHOD("last_error"), &VqaPlayer::last_error);
    ClassDB::bind_method(D_METHOD("width"), &VqaPlayer::width);
    ClassDB::bind_method(D_METHOD("height"), &VqaPlayer::height);
    ClassDB::bind_method(D_METHOD("frame_count"), &VqaPlayer::frame_count);
    ClassDB::bind_method(D_METHOD("fps"), &VqaPlayer::fps);
    ClassDB::bind_method(D_METHOD("get_length"), &VqaPlayer::get_length);
    ClassDB::bind_method(D_METHOD("audio_stream"), &VqaPlayer::audio_stream);
    ClassDB::bind_method(D_METHOD("seek", "frame"), &VqaPlayer::seek);
    ClassDB::bind_method(D_METHOD("next_frame"), &VqaPlayer::next_frame);
    ClassDB::bind_method(D_METHOD("current_frame"), &VqaPlayer::current_frame);
    ClassDB::bind_method(D_METHOD("frame_image"), &VqaPlayer::frame_image);
    ClassDB::bind_method(D_METHOD("blit_into", "image"), &VqaPlayer::blit_into);
}

bool VqaPlayer::open_buffer(const PackedByteArray& data) {
    std::vector<uint8_t> buf((const uint8_t*)data.ptr(), (const uint8_t*)data.ptr() + data.size());
    std::string err;
    open_ = dec_.open(std::move(buf), err);
    error_ = String(err.c_str());
    return open_;
}

bool VqaPlayer::open_file(const String& path) {
    const PackedByteArray data = FileAccess::get_file_as_bytes(path);
    if (data.is_empty()) {
        error_ = "Datei nicht lesbar: " + path;
        open_ = false;
        return false;
    }
    return open_buffer(data);
}

String VqaPlayer::last_error() const { return error_; }
int VqaPlayer::width() const { return dec_.width(); }
int VqaPlayer::height() const { return dec_.height(); }
int VqaPlayer::frame_count() const { return dec_.frame_count(); }
double VqaPlayer::fps() const { return dec_.fps(); }
double VqaPlayer::get_length() const { return dec_.length_seconds(); }
int VqaPlayer::current_frame() const { return dec_.current_frame(); }

Ref<AudioStreamWAV> VqaPlayer::audio_stream() const {
    if (!open_ || dec_.audio().empty()) {
        return Ref<AudioStreamWAV>();
    }
    Ref<AudioStreamWAV> wav;
    wav.instantiate();
    PackedByteArray pcm;
    pcm.resize((int64_t)dec_.audio().size());
    memcpy(pcm.ptrw(), dec_.audio().data(), dec_.audio().size());
    wav->set_format(AudioStreamWAV::FORMAT_16_BITS);
    wav->set_mix_rate(dec_.audio_rate());
    wav->set_stereo(dec_.audio_channels() == 2);
    wav->set_data(pcm);
    return wav;
}

bool VqaPlayer::seek(int frame) {
    if (!open_) {
        return false;
    }
    std::string err;
    const bool ok = dec_.seek(frame, err);
    if (!ok) {
        error_ = String(err.c_str());
    }
    return ok;
}

bool VqaPlayer::next_frame() {
    if (!open_) {
        return false;
    }
    std::string err;
    const bool ok = dec_.next_frame(err);
    if (!ok && !err.empty()) {
        error_ = String(err.c_str());
    }
    return ok;
}

Ref<Image> VqaPlayer::frame_image() {
    if (!open_) {
        return Ref<Image>();
    }
    std::vector<uint8_t> rgba;
    dec_.frame_rgba(rgba);
    rgba_.resize((int64_t)rgba.size());
    memcpy(rgba_.ptrw(), rgba.data(), rgba.size());
    return Image::create_from_data(dec_.width(), dec_.height(), false, Image::FORMAT_RGBA8, rgba_);
}

bool VqaPlayer::blit_into(const Ref<Image>& img) {
    if (!open_ || img.is_null()) {
        return false;
    }
    if (img->get_width() != dec_.width() || img->get_height() != dec_.height() ||
        img->get_format() != Image::FORMAT_RGBA8) {
        return false;
    }
    std::vector<uint8_t> rgba;
    dec_.frame_rgba(rgba);
    rgba_.resize((int64_t)rgba.size());
    memcpy(rgba_.ptrw(), rgba.data(), rgba.size());
    img->set_data(dec_.width(), dec_.height(), false, Image::FORMAT_RGBA8, rgba_);
    return true;
}

}

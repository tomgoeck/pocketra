

#pragma once

#include <godot_cpp/classes/audio_stream_wav.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include "../vqa.h"

namespace godot {

class VqaPlayer : public RefCounted {
    GDCLASS(VqaPlayer, RefCounted)

public:
    bool open_buffer(const PackedByteArray& data);
    bool open_file(const String& path);
    String last_error() const;

    int width() const;
    int height() const;
    int frame_count() const;
    double fps() const;
    double get_length() const;

    Ref<AudioStreamWAV> audio_stream() const;

    bool seek(int frame);
    bool next_frame();
    int current_frame() const;

    Ref<Image> frame_image();
    bool blit_into(const Ref<Image>& img);

protected:
    static void _bind_methods();

private:
    racontent::VqaDecoder dec_;
    String error_;
    bool open_ = false;
    PackedByteArray rgba_;
};

}

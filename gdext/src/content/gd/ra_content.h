

#pragma once

#include <godot_cpp/classes/audio_stream_wav.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <memory>
#include <string>
#include <vector>

#include "../atlas.h"
#include "../aud.h"
#include "../iso9660.h"
#include "../mix.h"
#include "../vqa.h"
#include "aud_stream.h"

namespace godot {

class RaContent : public RefCounted {
    GDCLASS(RaContent, RefCounted)

public:
    RaContent();

    String last_error() const;


    bool open_mix(const String& path);
    int open_dir(const String& dir);
    void close();
    PackedStringArray list(const String& mix_path = String()) const;
    bool has(const String& name) const;
    PackedByteArray read(const String& name) const;
    bool extract(const String& mix_path, const String& name, const String& out_path);
    Dictionary mix_info(const String& path);
    void set_names_path(const String& path);


    PackedStringArray iso_list(const String& iso_path);
    bool iso_extract(const String& iso_path, const String& entry, const String& out_path,
                     const Callable& progress = Callable());
    Dictionary iso_info(const String& iso_path);


    void set_recipe_dir(const String& dir);
    void set_bits_dir(const String& dir);
    void set_tilesets(const PackedStringArray& tilesets);
    bool build_atlases(const String& mix_dir, const String& out_dir,
                       const Callable& progress = Callable());


    void set_force_english(const PackedStringArray& names);
    bool convert_sounds(const String& mix_dir, const String& out_dir, const PackedStringArray& names,
                        const String& lang = String(), const Callable& progress = Callable());
    bool convert_sound(const String& name, const String& out_path);


    Ref<AudStream> aud_stream(const String& name);
    PackedByteArray movie_bytes(const String& name);
    PackedStringArray list_music() const;
    PackedStringArray list_movies() const;


    Dictionary scan(const String& mix_dir);
    bool write_manifest(const String& dir, const Dictionary& extra = Dictionary());
    static Dictionary content_status(const String& dir);


    static String system_path(const String& path);


    static int64_t free_space(const String& path);

protected:
    static void _bind_methods();

private:
    void report(const char* stage, float fraction, const String& detail, const Callable& progress);
    bool ensure_names();
    racontent::ProgressFn make_progress(const Callable& progress);

    std::shared_ptr<racontent::NameDatabase> names_;
    racontent::ContentSet content_;
    String names_path_ = "res://data/mix_names.dat";
    String recipe_dir_ = "res://data/atlas";
    String bits_dir_ = "res://data/bits";
    PackedStringArray tilesets_;
    PackedStringArray force_english_;
    String error_;
    Dictionary last_scan_;
    Dictionary built_;
};

}

#include "ra_content.h"

#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#if defined(__EMSCRIPTEN__)


#elif defined(_WIN32)
#include <windows.h>
#else
#include <sys/statvfs.h>
#endif

#include "../platform.h"

namespace godot {

using namespace racontent;


static std::string to_std(const String& s) { return std::string(s.utf8().get_data()); }
static String to_gd(const std::string& s) { return String::utf8(s.c_str()); }


static bool is_pack_path(const String& p) { return p.begins_with("res://"); }

static bool read_godot_file(const String& path, std::vector<uint8_t>& out) {
    const PackedByteArray data = FileAccess::get_file_as_bytes(path);
    if (data.is_empty()) {
        return FileAccess::file_exists(path);
    }
    out.assign((const uint8_t*)data.ptr(), (const uint8_t*)data.ptr() + data.size());
    return true;
}

String RaContent::system_path(const String& path) {
    if (path.begins_with("res://") || path.begins_with("user://")) {
        return ProjectSettings::get_singleton()->globalize_path(path);
    }
    return path;
}


int64_t RaContent::free_space(const String& path) {
#if defined(__EMSCRIPTEN__)

    (void)path;
    return -1;
#elif defined(_WIN32)


    const CharWideString wide = system_path(path).wide_string();
    ULARGE_INTEGER avail;
    avail.QuadPart = 0;
    if (!GetDiskFreeSpaceExW(wide.get_data(), &avail, nullptr, nullptr)) {
        return -1;
    }
    return (int64_t)avail.QuadPart;
#else
    struct statvfs st;
    if (statvfs(to_std(system_path(path)).c_str(), &st) != 0) {
        return -1;
    }

    const uint64_t unit = st.f_frsize != 0 ? (uint64_t)st.f_frsize : (uint64_t)st.f_bsize;
    return (int64_t)((uint64_t)st.f_bavail * unit);
#endif
}


static bool read_any(const String& path, std::vector<uint8_t>& out) {
    if (is_pack_path(path)) {
        return read_godot_file(path, out);
    }
    return read_whole_file(to_std(RaContent::system_path(path)), out);
}


void RaContent::_bind_methods() {
    ClassDB::bind_method(D_METHOD("last_error"), &RaContent::last_error);
    ClassDB::bind_method(D_METHOD("open_mix", "path"), &RaContent::open_mix);
    ClassDB::bind_method(D_METHOD("open_dir", "dir"), &RaContent::open_dir);
    ClassDB::bind_method(D_METHOD("close"), &RaContent::close);
    ClassDB::bind_method(D_METHOD("list", "mix_path"), &RaContent::list, DEFVAL(String()));
    ClassDB::bind_method(D_METHOD("has", "name"), &RaContent::has);
    ClassDB::bind_method(D_METHOD("read", "name"), &RaContent::read);
    ClassDB::bind_method(D_METHOD("extract", "mix_path", "name", "out_path"), &RaContent::extract);
    ClassDB::bind_method(D_METHOD("mix_info", "path"), &RaContent::mix_info);
    ClassDB::bind_method(D_METHOD("set_names_path", "path"), &RaContent::set_names_path);

    ClassDB::bind_method(D_METHOD("iso_list", "iso_path"), &RaContent::iso_list);
    ClassDB::bind_method(D_METHOD("iso_extract", "iso_path", "entry", "out_path", "progress"),
                         &RaContent::iso_extract, DEFVAL(Callable()));
    ClassDB::bind_method(D_METHOD("iso_info", "iso_path"), &RaContent::iso_info);

    ClassDB::bind_method(D_METHOD("set_recipe_dir", "dir"), &RaContent::set_recipe_dir);
    ClassDB::bind_method(D_METHOD("set_bits_dir", "dir"), &RaContent::set_bits_dir);
    ClassDB::bind_method(D_METHOD("set_tilesets", "tilesets"), &RaContent::set_tilesets);
    ClassDB::bind_method(D_METHOD("set_web_pages", "on"), &RaContent::set_web_pages);
    ClassDB::bind_method(D_METHOD("reset_built"), &RaContent::reset_built);
    ClassDB::bind_method(D_METHOD("build_atlases", "mix_dir", "out_dir", "progress"),
                         &RaContent::build_atlases, DEFVAL(Callable()));

    ClassDB::bind_method(D_METHOD("set_force_english", "names"), &RaContent::set_force_english);
    ClassDB::bind_method(D_METHOD("convert_sounds", "mix_dir", "out_dir", "names", "lang", "progress"),
                         &RaContent::convert_sounds, DEFVAL(String()), DEFVAL(Callable()));
    ClassDB::bind_method(D_METHOD("convert_sound", "name", "out_path"), &RaContent::convert_sound);

    ClassDB::bind_method(D_METHOD("aud_stream", "name"), &RaContent::aud_stream);
    ClassDB::bind_method(D_METHOD("movie_bytes", "name"), &RaContent::movie_bytes);
    ClassDB::bind_method(D_METHOD("list_music"), &RaContent::list_music);
    ClassDB::bind_method(D_METHOD("list_movies"), &RaContent::list_movies);

    ClassDB::bind_method(D_METHOD("scan", "mix_dir"), &RaContent::scan);
    ClassDB::bind_method(D_METHOD("write_manifest", "dir", "extra"), &RaContent::write_manifest,
                         DEFVAL(Dictionary()));
    ClassDB::bind_static_method("RaContent", D_METHOD("content_status", "dir"), &RaContent::content_status,
                                DEFVAL(String("user://content")));
    ClassDB::bind_static_method("RaContent", D_METHOD("system_path", "path"), &RaContent::system_path);
    ClassDB::bind_static_method("RaContent", D_METHOD("free_space", "path"), &RaContent::free_space);

    ADD_SIGNAL(MethodInfo("progress", PropertyInfo(Variant::STRING, "stage"),
                          PropertyInfo(Variant::FLOAT, "fraction"), PropertyInfo(Variant::STRING, "detail")));
}

RaContent::RaContent() {
    tilesets_.push_back("temperat");
    tilesets_.push_back("snow");
    tilesets_.push_back("interior");


}

String RaContent::last_error() const { return error_; }

void RaContent::report(const char* stage, float fraction, const String& detail,
                       const Callable& progress) {
    emit_signal("progress", String(stage), fraction, detail);
    if (progress.is_valid()) {
        progress.call(String(stage), fraction, detail);
    }
}

ProgressFn RaContent::make_progress(const Callable& progress) {

    return [this, progress](const char* stage, float f, const std::string& detail) {
        report(stage, f, to_gd(detail), progress);
    };
}

bool RaContent::ensure_names() {
    if (names_) {
        return true;
    }
    std::vector<uint8_t> data;
    if (!read_any(names_path_, data) || data.empty()) {
        error_ = "Namensverzeichnis fehlt: " + names_path_;
        return false;
    }
    names_ = std::make_shared<NameDatabase>();
    if (!names_->load_bytes(data.data(), data.size())) {
        names_.reset();
        error_ = "Namensverzeichnis unbrauchbar: " + names_path_;
        return false;
    }
    content_.set_names(names_);
    return true;
}

void RaContent::set_names_path(const String& path) {
    names_path_ = path;
    names_.reset();
}


bool RaContent::open_mix(const String& path) {
    if (!ensure_names()) {
        return false;
    }
    std::string err;
    if (!content_.add_file(to_std(system_path(path)), err)) {
        error_ = to_gd(err);
        return false;
    }
    return true;
}

int RaContent::open_dir(const String& dir) {
    if (!ensure_names()) {
        return 0;
    }
    std::string err;
    const int n = content_.add_dir(to_std(system_path(dir)), err);
    if (n == 0) {
        error_ = to_gd(err);
    }
    return n;
}

void RaContent::close() { content_.clear(); }

PackedStringArray RaContent::list(const String& mix_path) const {
    PackedStringArray out;
    if (mix_path.is_empty()) {
        for (const std::string& n : content_.list()) {
            out.push_back(to_gd(n));
        }
        return out;
    }
    ContentSet one;
    one.set_names(names_);
    std::string err;
    if (!one.add_file(to_std(system_path(mix_path)), err)) {
        return out;
    }
    for (const std::string& n : one.list()) {
        out.push_back(to_gd(n));
    }
    return out;
}

bool RaContent::has(const String& name) const { return content_.has(to_std(name)); }

PackedByteArray RaContent::read(const String& name) const {
    PackedByteArray out;
    std::vector<uint8_t> data;
    if (!content_.read(to_std(name), data)) {
        return out;
    }
    out.resize((int64_t)data.size());
    if (!data.empty()) {
        memcpy(out.ptrw(), data.data(), data.size());
    }
    return out;
}

bool RaContent::extract(const String& mix_path, const String& name, const String& out_path) {
    std::vector<uint8_t> data;
    bool ok = false;
    if (mix_path.is_empty()) {
        ok = content_.read(to_std(name), data);
    } else {
        if (!ensure_names()) {
            return false;
        }
        ContentSet one;
        one.set_names(names_);
        std::string err;
        if (!one.add_file(to_std(system_path(mix_path)), err)) {
            error_ = to_gd(err);
            return false;
        }
        ok = one.read(to_std(name), data);
    }
    if (!ok) {
        error_ = name + String(" nicht im Archiv");
        return false;
    }
    if (!write_whole_file(to_std(system_path(out_path)), data.data(), data.size())) {
        error_ = "nicht schreibbar: " + out_path;
        return false;
    }
    return true;
}

Dictionary RaContent::mix_info(const String& path) {
    Dictionary d;
    d["ok"] = false;
    if (!ensure_names()) {
        return d;
    }
    auto src = FileSource::open(to_std(system_path(path)));
    if (!src) {
        error_ = "Datei nicht lesbar: " + path;
        return d;
    }
    MixArchive mix;
    std::string err;
    if (!mix.parse(src, 0, src->size(), names_.get(), err)) {
        error_ = to_gd(err);
        return d;
    }
    d["ok"] = true;
    d["files"] = (int)mix.entries().size();
    d["named"] = (int)mix.named();
    d["encrypted"] = mix.encrypted();
    d["format"] = mix.td_format() ? "td" : "ra";
    return d;
}


PackedStringArray RaContent::iso_list(const String& iso_path) {
    PackedStringArray out;
    IsoImage iso;
    std::string err;
    if (!iso.open(to_std(system_path(iso_path)), err)) {
        error_ = to_gd(err);
        return out;
    }
    for (const IsoEntry& e : iso.entries()) {
        out.push_back(to_gd(e.path));
    }
    return out;
}

Dictionary RaContent::iso_info(const String& iso_path) {
    Dictionary d;
    d["ok"] = false;
    IsoImage iso;
    std::string err;
    if (!iso.open(to_std(system_path(iso_path)), err)) {
        error_ = to_gd(err);
        return d;
    }
    uint64_t total = 0;
    for (const IsoEntry& e : iso.entries()) {
        total += e.size;
    }
    d["ok"] = true;
    d["label"] = to_gd(iso.label());
    d["entries"] = (int)iso.entries().size();
    d["size"] = (int64_t)total;
    return d;
}

bool RaContent::iso_extract(const String& iso_path, const String& entry, const String& out_path,
                            const Callable& progress) {
    IsoImage iso;
    std::string err;
    if (!iso.open(to_std(system_path(iso_path)), err)) {
        error_ = to_gd(err);
        return false;
    }
    const IsoEntry* e = iso.find(to_std(entry));
    if (!e) {
        error_ = entry + String(" nicht im Abbild");
        return false;
    }
    const String detail = entry;
    const bool ok = iso.extract(*e, to_std(system_path(out_path)),
                                [this, &progress, &detail](float f) { report("iso", f, detail, progress); },
                                err);
    if (!ok) {
        error_ = to_gd(err);
    }
    return ok;
}


void RaContent::set_recipe_dir(const String& dir) { recipe_dir_ = dir; }
void RaContent::set_bits_dir(const String& dir) { bits_dir_ = dir; }
void RaContent::set_tilesets(const PackedStringArray& tilesets) { tilesets_ = tilesets; }
void RaContent::set_web_pages(bool on) { web_pages_ = on; }


void RaContent::reset_built() { built_.clear(); }

bool RaContent::build_atlases(const String& mix_dir, const String& out_dir, const Callable& progress) {
    if (!mix_dir.is_empty()) {
        content_.clear();
        if (open_dir(mix_dir) == 0) {
            return false;
        }
    }
    AtlasBuilder b;
    b.set_recipe_dir(to_std(recipe_dir_));
    b.set_bits_dir(to_std(bits_dir_));
    b.set_web_pages(web_pages_);

    b.set_asset_reader([](const std::string& path, std::vector<uint8_t>& out) {
        return read_any(to_gd(path), out) && !out.empty();
    });

    std::vector<std::string> tilesets;
    for (int i = 0; i < tilesets_.size(); ++i) {
        tilesets.push_back(to_std(tilesets_[i]));
    }
    std::string err;
    const ProgressFn fn = make_progress(progress);
    const bool ok = b.build(content_, tilesets, to_std(system_path(out_dir)), fn, err);
    if (!ok) {
        error_ = to_gd(err);
        return false;
    }


    Array atlases = built_.get("atlases", Array());
    for (const std::string& t : tilesets) {
        if (!atlases.has(to_gd(t))) {
            atlases.push_back(to_gd(t));
        }
    }
    built_["atlases"] = atlases;
    if (!b.missing().empty()) {
        Array missing;
        for (size_t i = 0; i < b.missing().size() && i < 40; ++i) {
            missing.push_back(to_gd(b.missing()[i]));
        }
        built_["atlas_missing"] = missing;
    }
    return true;
}


void RaContent::set_force_english(const PackedStringArray& names) { force_english_ = names; }


static String sound_target_name(const String& name) {
    if (name.to_lower().ends_with(".aud")) {
        return name.get_basename();
    }
    return name.replace(".", "_");
}

bool RaContent::convert_sound(const String& name, const String& out_path) {
    std::vector<uint8_t> raw;
    if (!content_.read(to_std(name), raw)) {
        error_ = name + String(" nicht im Archiv");
        return false;
    }
    AudClip clip;
    std::string err;
    if (!decode_aud(raw.data(), raw.size(), clip, err)) {
        error_ = to_gd(err);
        return false;
    }
    std::vector<uint8_t> wav;
    pcm_to_wav(clip, wav);
    if (!write_whole_file(to_std(system_path(out_path)), wav.data(), wav.size())) {
        error_ = "nicht schreibbar: " + out_path;
        return false;
    }
    return true;
}

bool RaContent::convert_sounds(const String& mix_dir, const String& out_dir,
                               const PackedStringArray& names, const String& lang,
                               const Callable& progress) {
    if (!mix_dir.is_empty()) {
        content_.clear();
        if (open_dir(mix_dir) == 0) {
            return false;
        }
    }
    PackedStringArray list = names;
    if (list.is_empty()) {
        std::vector<uint8_t> data;
        if (read_any("res://data/sounds.txt", data) && !data.empty()) {
            const String text = String::utf8((const char*)data.data(), (int64_t)data.size());
            for (const String& line : text.split("\n", false)) {
                const String t = line.strip_edges();
                if (!t.is_empty() && !t.begins_with("#")) {
                    list.push_back(t);
                }
            }
        }
    }
    if (list.is_empty()) {
        error_ = "keine Soundliste (res://data/sounds.txt fehlt)";
        return false;
    }

    const String target_dir = lang.is_empty() ? out_dir : out_dir.path_join(lang);
    int ok = 0, missing = 0;
    for (int i = 0; i < list.size(); ++i) {
        const String& name = list[i];
        if (i % 16 == 0) {
            report("sfx", (float)i / (float)list.size(), name, progress);
        }


        bool skip = false;
        if (!lang.is_empty()) {
            for (int k = 0; k < force_english_.size(); ++k) {
                if (name.to_lower().begins_with(force_english_[k].to_lower())) {
                    skip = true;
                    break;
                }
            }
        }
        if (skip) {
            continue;
        }
        const String out = target_dir.path_join(sound_target_name(name) + ".wav");
        if (convert_sound(name, out)) {
            ++ok;
        } else {
            ++missing;
        }
    }
    report("sfx", 1.0f, String(), progress);


    const String sfx_key = lang.is_empty() ? String("sfx") : String("sfx_") + lang;
    built_[sfx_key] = (int)built_.get(sfx_key, 0) + ok;
    if (ok == 0) {
        error_ = "kein einziger Sound gewandelt";
        return false;
    }
    (void)missing;
    return true;
}


Ref<AudStream> RaContent::aud_stream(const String& name) {
    std::vector<uint8_t> raw;
    if (!content_.read(to_std(name), raw)) {
        error_ = name + String(" nicht im Archiv");
        return Ref<AudStream>();
    }
    Ref<AudStream> s;
    s.instantiate();
    if (!s->set_data(std::move(raw))) {
        error_ = name + String(": kein AUD");
        return Ref<AudStream>();
    }
    return s;
}

PackedByteArray RaContent::movie_bytes(const String& name) {
    String n = name;
    if (!n.to_lower().ends_with(".vqa")) {
        n += ".vqa";
    }
    return read(n);
}

PackedStringArray RaContent::list_music() const {
    PackedStringArray out;
    for (const auto& m : content_.archives()) {
        if (String(to_gd(m->label())).to_lower().find("scores.mix") < 0) {
            continue;
        }
        for (const auto& e : m->entries()) {
            if (!e.name.empty() && extension(e.name) == "aud") {
                out.push_back(to_gd(e.name));
            }
        }
    }
    out.sort();
    return out;
}

PackedStringArray RaContent::list_movies() const {
    PackedStringArray out;
    for (const std::string& n : content_.list()) {
        if (extension(n) == "vqa") {
            out.push_back(to_gd(n));
        }
    }
    return out;
}


Dictionary RaContent::scan(const String& mix_dir) {
    Dictionary d;
    if (!mix_dir.is_empty()) {
        content_.clear();
        open_dir(mix_dir);
    }


    const char* markers[] = {"2tnk.shp",    "clear1.tem",   "clear1.sno", "clear1.int",
                             "cannon1.aud", "temperat.pal", "rules.ini"};
    Array missing;
    bool freeware = true;
    for (const char* m : markers) {
        if (!content_.has(m)) {
            missing.push_back(String(m));
            freeware = false;
        }
    }

    const bool music = content_.has("bigf226m.aud") || content_.has("hell226m.aud");
    int vqa = 0;
    for (const std::string& n : content_.list()) {
        if (extension(n) == "vqa") {
            ++vqa;
        }
    }
    const bool movies = vqa > 0;


    bool cd1 = false, cd2 = false;
    for (const auto& m : content_.archives()) {
        const std::string l = lower(m->label());
        if (l.find("movies1.mix") != std::string::npos) {
            cd1 = true;
        }
        if (l.find("movies2.mix") != std::string::npos) {
            cd2 = true;
        }
    }

    Array languages;
    languages.push_back("en");

    size_t files = 0;
    for (const auto& m : content_.archives()) {
        files += m->entries().size();
    }

    d["freeware"] = freeware;
    d["cd1"] = cd1;
    d["cd2"] = cd2;
    d["movies"] = movies;
    d["movie_count"] = vqa;
    d["music"] = music;
    d["languages"] = languages;
    d["archives"] = (int)content_.archives().size();
    d["files"] = (int)files;
    d["missing"] = missing;
    last_scan_ = d;
    return d;
}

bool RaContent::write_manifest(const String& dir, const Dictionary& extra) {
    Dictionary m = last_scan_.duplicate();
    const Array keys = built_.keys();
    for (int i = 0; i < keys.size(); ++i) {
        m[keys[i]] = built_[keys[i]];
    }
    const Array ekeys = extra.keys();
    for (int i = 0; i < ekeys.size(); ++i) {
        m[ekeys[i]] = extra[ekeys[i]];
    }
    m["format"] = 1;
    m["written"] = Time::get_singleton()->get_datetime_string_from_system(true);
    const String json = JSON::stringify(m, "\t");
    const CharString utf8 = json.utf8();
    return write_whole_file(to_std(system_path(dir.path_join("manifest.json"))),
                            (const uint8_t*)utf8.get_data(), (size_t)utf8.length());
}

Dictionary RaContent::content_status(const String& dir) {
    Dictionary d;
    d["dir"] = dir;
    Dictionary manifest;
    const String mpath = dir.path_join("manifest.json");
    if (FileAccess::file_exists(mpath)) {
        const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(mpath));
        if (parsed.get_type() == Variant::DICTIONARY) {
            manifest = parsed;
        }
    }
    d["manifest"] = manifest;


    Array atlases;
    for (const String& t : {String("temperat"), String("snow"), String("interior")}) {
        const bool pixels = FileAccess::file_exists(dir.path_join("atlas/atlas_" + t + ".r8")) ||
                            FileAccess::file_exists(dir.path_join("atlas/atlas_" + t + "_web_0.r8"));
        if (FileAccess::file_exists(dir.path_join("atlas/atlas_" + t + ".json")) && pixels &&
            FileAccess::file_exists(dir.path_join("atlas/" + t + ".rgba"))) {
            atlases.push_back(t);
        }
    }
    d["atlases"] = atlases;

    int sfx = 0;
    Array languages;
    Ref<DirAccess> da = DirAccess::open(dir.path_join("sfx"));
    if (da.is_valid()) {
        for (const String& f : da->get_files()) {
            if (f.ends_with(".wav")) {
                ++sfx;
            }
        }
        for (const String& sub : da->get_directories()) {
            languages.push_back(sub);
        }
    }
    d["sfx"] = sfx;
    d["languages"] = languages;
    d["freeware"] = manifest.get("freeware", false);
    d["cd1"] = manifest.get("cd1", false);
    d["cd2"] = manifest.get("cd2", false);
    d["ready"] = atlases.size() == 3 && sfx > 0;
    return d;
}

}



#include <cinttypes>
#include <cstdio>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

#include "../src/content/atlas.h"
#include "../src/content/aud.h"
#include "../src/content/mix.h"
#include "../src/content/platform.h"
#include "../src/content/sprites.h"
#include "../src/content/vqa.h"

using namespace racontent;

static int usage() {
    std::fprintf(stderr, "usage: test_content <names|list|dump|pal|aud|atlas|vqa> …\n");
    return 2;
}

static bool open_content(const std::string& db, const std::string& dir, ContentSet& cs) {
    auto names = std::make_shared<NameDatabase>();
    if (!names->load(db)) {
        std::fprintf(stderr, "Namensdatenbank %s nicht lesbar\n", db.c_str());
        return false;
    }
    cs.set_names(names);
    std::string err;
    const int n = cs.add_dir(dir, err);
    if (n == 0) {
        std::fprintf(stderr, "keine Archive unter %s: %s\n", dir.c_str(), err.c_str());
        return false;
    }
    return true;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        return usage();
    }
    const std::string cmd = argv[1];

    if (cmd == "names") {
        NameDatabase db;
        if (!db.load(argv[2])) {
            return 1;
        }
        std::printf("entries=%zu\n", db.size());
        const char* probe[] = {"conquer.mix", "2tnk.shp", "temperat.pal", "clear1.tem", "redintro.vqa"};
        for (const char* p : probe) {
            std::printf("%s %08x\n", p, classic_hash(p));
        }
        return 0;
    }

    if (argc < 4) {
        return usage();
    }
    ContentSet cs;
    if (!open_content(argv[2], argv[3], cs)) {
        return 1;
    }

    if (cmd == "list") {
        size_t files = 0;
        for (const auto& m : cs.archives()) {
            files += m->entries().size();
        }
        std::printf("archives=%zu files=%zu\n", cs.archives().size(), files);
        for (const std::string& n : cs.list()) {
            std::printf("%s\n", n.c_str());
        }
        return 0;
    }

    if (cmd == "dump" && argc >= 6) {
        std::vector<uint8_t> raw;
        if (!cs.read(argv[4], raw)) {
            std::fprintf(stderr, "%s nicht gefunden\n", argv[4]);
            return 1;
        }
        FrameSet fs;
        std::string err;
        if (!load_frames(raw.data(), raw.size(), argv[4], fs, err)) {
            std::fprintf(stderr, "%s: %s\n", argv[4], err.c_str());
            return 1;
        }
        std::vector<uint8_t> out;
        auto put32 = [&out](uint32_t v) {
            out.push_back((uint8_t)v);
            out.push_back((uint8_t)(v >> 8));
            out.push_back((uint8_t)(v >> 16));
            out.push_back((uint8_t)(v >> 24));
        };
        put32((uint32_t)fs.width);
        put32((uint32_t)fs.height);
        put32((uint32_t)fs.frames.size());
        for (const auto& f : fs.frames) {
            out.insert(out.end(), f.begin(), f.end());
        }
        return write_whole_file(argv[5], out.data(), out.size()) ? 0 : 1;
    }

    if (cmd == "dumpall" && argc >= 6) {

        std::vector<uint8_t> list;
        if (!read_whole_file(argv[4], list)) {
            return 1;
        }
        std::vector<uint8_t> out;
        auto put32 = [&out](uint32_t v) {
            out.push_back((uint8_t)v);
            out.push_back((uint8_t)(v >> 8));
            out.push_back((uint8_t)(v >> 16));
            out.push_back((uint8_t)(v >> 24));
        };
        std::string text((const char*)list.data(), list.size()), name;
        std::istringstream in(text);
        int ok = 0, miss = 0;
        while (std::getline(in, name)) {
            while (!name.empty() && (name.back() == '\r' || name.back() == ' ')) {
                name.pop_back();
            }
            if (name.empty()) {
                continue;
            }
            std::vector<uint8_t> raw;
            FrameSet fs;
            std::string err;
            if (!cs.read(name, raw) || !load_frames(raw.data(), raw.size(), name, fs, err)) {
                ++miss;
                continue;
            }
            ++ok;
            for (char c : name) {
                out.push_back((uint8_t)c);
            }
            out.push_back(0);
            put32((uint32_t)fs.width);
            put32((uint32_t)fs.height);
            put32((uint32_t)fs.frames.size());
            for (const auto& f : fs.frames) {
                out.insert(out.end(), f.begin(), f.end());
            }
        }
        std::fprintf(stderr, "dumpall: %d gelesen, %d nicht im MIX\n", ok, miss);
        return write_whole_file(argv[5], out.data(), out.size()) ? 0 : 1;
    }

    if (cmd == "pal" && argc >= 6) {
        std::vector<uint8_t> raw, rgba;
        if (!cs.read(argv[4], raw) || !palette_to_rgba(raw.data(), raw.size(), rgba)) {
            return 1;
        }
        return write_whole_file(argv[5], rgba.data(), rgba.size()) ? 0 : 1;
    }

    if (cmd == "aud" && argc >= 6) {
        std::vector<uint8_t> raw;
        if (!cs.read(argv[4], raw)) {
            std::fprintf(stderr, "%s nicht gefunden\n", argv[4]);
            return 1;
        }
        AudClip clip;
        std::string err;
        if (!decode_aud(raw.data(), raw.size(), clip, err)) {
            std::fprintf(stderr, "%s: %s\n", argv[4], err.c_str());
            return 1;
        }
        std::vector<uint8_t> wav;
        pcm_to_wav(clip, wav);
        std::printf("rate=%d channels=%d samples=%zu\n", clip.sample_rate, clip.channels,
                    clip.pcm.size());
        return write_whole_file(argv[5], wav.data(), wav.size()) ? 0 : 1;
    }

    if (cmd == "atlas" && argc >= 7) {
        AtlasBuilder b;
        b.set_recipe_dir(argv[4]);
        b.set_bits_dir(argv[5]);
        std::vector<std::string> tilesets;
        for (int i = 7; i < argc; ++i) {
            tilesets.push_back(argv[i]);
        }
        if (tilesets.empty()) {
            tilesets = {"temperat", "snow", "interior"};
        }
        std::string err;
        const bool ok = b.build(cs, tilesets, argv[6], nullptr, err);
        if (!ok) {
            std::fprintf(stderr, "atlas: %s\n", err.c_str());
        }
        for (const std::string& m : b.missing()) {
            std::fprintf(stderr, "  fehlt: %s\n", m.c_str());
        }
        return ok ? 0 : 1;
    }

    if (cmd == "vqa" && argc >= 6) {
        std::vector<uint8_t> raw;
        if (!cs.read(argv[4], raw)) {
            std::fprintf(stderr, "%s nicht gefunden\n", argv[4]);
            return 1;
        }
        VqaDecoder v;
        std::string err;
        if (!v.open(std::move(raw), err)) {
            std::fprintf(stderr, "%s: %s\n", argv[4], err.c_str());
            return 1;
        }
        const int limit = argc >= 7 ? std::atoi(argv[6]) : 4;
        std::printf("size=%dx%d frames=%d fps=%d audio=%d/%dch\n", v.width(), v.height(),
                    v.frame_count(), v.fps(), v.audio_rate(), v.audio_channels());
        make_dirs(argv[5]);
        for (int i = 0; i < limit && v.next_frame(err); ++i) {
            std::vector<uint8_t> rgba;
            v.frame_rgba(rgba);
            char path[1024];
            std::snprintf(path, sizeof(path), "%s/frame%03d.rgba", argv[5], i);
            write_whole_file(path, rgba.data(), rgba.size());
        }
        std::vector<uint8_t> pcm;
        v.take_audio(pcm);
        char path[1024];
        std::snprintf(path, sizeof(path), "%s/audio.pcm", argv[5]);
        write_whole_file(path, pcm.data(), pcm.size());
        std::printf("audio_bytes=%zu\n", pcm.size());
        return 0;
    }

    return usage();
}

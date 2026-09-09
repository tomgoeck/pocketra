#include "platform.h"

#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>
#ifdef _WIN32


#include <direct.h>
#define RA_MKDIR(p) ::_mkdir(p)
#else
#define RA_MKDIR(p) ::mkdir((p), 0755)
#endif

#include <algorithm>
#include <cctype>
#include <cstdio>

namespace racontent {

std::string lower(const std::string& s) {
    std::string o = s;
    for (char& c : o) {
        c = (char)std::tolower((unsigned char)c);
    }
    return o;
}

bool read_whole_file(const std::string& path, std::vector<uint8_t>& out) {
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) {
        return false;
    }
    std::fseek(f, 0, SEEK_END);
    const long size = std::ftell(f);
    std::fseek(f, 0, SEEK_SET);
    out.resize(size > 0 ? (size_t)size : 0);
    const bool ok = size <= 0 || std::fread(out.data(), 1, out.size(), f) == out.size();
    std::fclose(f);
    return ok;
}

bool write_whole_file(const std::string& path, const uint8_t* data, size_t len) {
    const size_t slash = path.find_last_of('/');
    if (slash != std::string::npos) {
        make_dirs(path.substr(0, slash));
    }
    FILE* f = std::fopen(path.c_str(), "wb");
    if (!f) {
        return false;
    }
    const bool ok = len == 0 || std::fwrite(data, 1, len, f) == len;
    std::fclose(f);
    return ok;
}

bool file_exists(const std::string& path) {
    struct stat st;
    return ::stat(path.c_str(), &st) == 0 && S_ISREG(st.st_mode);
}

bool dir_exists(const std::string& path) {
    struct stat st;
    return ::stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

bool make_dirs(const std::string& path) {
    if (path.empty() || dir_exists(path)) {
        return true;
    }
    std::string cur;
    for (size_t i = 0; i < path.size(); ++i) {
        cur.push_back(path[i]);
        if (path[i] == '/' && cur.size() > 1) {
            RA_MKDIR(cur.c_str());
        }
    }
    RA_MKDIR(path.c_str());
    return dir_exists(path);
}

void list_files(const std::string& dir, std::vector<std::string>& out) {
    DIR* d = ::opendir(dir.c_str());
    if (!d) {
        return;
    }
    while (struct dirent* e = ::readdir(d)) {
        const std::string name = e->d_name;
        if (name == "." || name == "..") {
            continue;
        }
        if (file_exists(join_path(dir, name))) {
            out.push_back(name);
        }
    }
    ::closedir(d);
    std::sort(out.begin(), out.end());
}

void list_files_recursive(const std::string& dir, std::vector<std::string>& out) {
    DIR* d = ::opendir(dir.c_str());
    if (!d) {
        return;
    }
    std::vector<std::string> subdirs;
    while (struct dirent* e = ::readdir(d)) {
        const std::string name = e->d_name;
        if (name == "." || name == ".." || (!name.empty() && name[0] == '.')) {
            continue;
        }
        const std::string full = join_path(dir, name);
        if (dir_exists(full)) {
            subdirs.push_back(full);
        } else if (file_exists(full)) {
            out.push_back(full);
        }
    }
    ::closedir(d);
    std::sort(subdirs.begin(), subdirs.end());
    for (const std::string& s : subdirs) {
        list_files_recursive(s, out);
    }
}

std::string base_name(const std::string& path) {
    const size_t slash = path.find_last_of('/');
    return slash == std::string::npos ? path : path.substr(slash + 1);
}

std::string stem(const std::string& path) {
    const std::string b = base_name(path);
    const size_t dot = b.find_last_of('.');
    return dot == std::string::npos ? b : b.substr(0, dot);
}

std::string extension(const std::string& path) {
    const std::string b = base_name(path);
    const size_t dot = b.find_last_of('.');
    return dot == std::string::npos ? std::string() : lower(b.substr(dot + 1));
}

std::string join_path(const std::string& a, const std::string& b) {
    if (a.empty()) {
        return b;
    }
    if (!a.empty() && a.back() == '/') {
        return a + b;
    }
    return a + "/" + b;
}

}

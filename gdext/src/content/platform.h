

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace racontent {

bool read_whole_file(const std::string& path, std::vector<uint8_t>& out);
bool write_whole_file(const std::string& path, const uint8_t* data, size_t len);
bool file_exists(const std::string& path);
bool dir_exists(const std::string& path);
bool make_dirs(const std::string& path);
void list_files_recursive(const std::string& dir, std::vector<std::string>& out);
void list_files(const std::string& dir, std::vector<std::string>& out);
std::string base_name(const std::string& path);
std::string stem(const std::string& path);
std::string extension(const std::string& path);
std::string join_path(const std::string& a, const std::string& b);
std::string lower(const std::string& s);

}

// POSIX implementation of reader::fs.

#include "reader/file_system.h"

#ifndef _WIN32

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <pwd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <string>

#include "reader/platform.h"

namespace reader {
namespace fs {

static std::string w_to_utf8(const wchar_t* w) {
    std::string out;
    if (!w) return out;
    for (; *w; ++w) {
        uint32_t c = (uint32_t)*w;
        if (c < 0x80) out.push_back((char)c);
        else if (c < 0x800) {
            out.push_back((char)(0xC0 | (c >> 6)));
            out.push_back((char)(0x80 | (c & 0x3F)));
        } else if (c < 0x10000) {
            out.push_back((char)(0xE0 | (c >> 12)));
            out.push_back((char)(0x80 | ((c >> 6) & 0x3F)));
            out.push_back((char)(0x80 | (c & 0x3F)));
        } else {
            out.push_back((char)(0xF0 | (c >> 18)));
            out.push_back((char)(0x80 | ((c >> 12) & 0x3F)));
            out.push_back((char)(0x80 | ((c >> 6) & 0x3F)));
            out.push_back((char)(0x80 | (c & 0x3F)));
        }
    }
    return out;
}

static void utf8_to_w(const char* s, wchar_t* out, size_t out_cap) {
    size_t i = 0;
    while (*s && i + 1 < out_cap) {
        unsigned char c = (unsigned char)*s;
        uint32_t cp = 0;
        int extra = 0;
        if (c < 0x80) { cp = c; extra = 0; }
        else if ((c & 0xE0) == 0xC0) { cp = c & 0x1F; extra = 1; }
        else if ((c & 0xF0) == 0xE0) { cp = c & 0x0F; extra = 2; }
        else if ((c & 0xF8) == 0xF0) { cp = c & 0x07; extra = 3; }
        else { ++s; continue; }
        ++s;
        for (int k = 0; k < extra; ++k) {
            if ((*s & 0xC0) != 0x80) { cp = '?'; break; }
            cp = (cp << 6) | (*s & 0x3F);
            ++s;
        }
        out[i++] = (wchar_t)cp;
    }
    out[i] = 0;
}

char* read_all(const TCHAR* path, int* out_size) {
    if (out_size) *out_size = 0;
    FILE* fp = std::fopen(w_to_utf8(path).c_str(), "rb");
    if (!fp) return nullptr;
    std::fseek(fp, 0, SEEK_END);
    long sz = std::ftell(fp);
    std::fseek(fp, 0, SEEK_SET);
    if (sz < 0) { std::fclose(fp); return nullptr; }
    char* buf = (char*)std::malloc((size_t)sz + 1);
    if (!buf) { std::fclose(fp); return nullptr; }
    size_t got = std::fread(buf, 1, (size_t)sz, fp);
    std::fclose(fp);
    buf[got] = 0;
    if (out_size) *out_size = (int)got;
    return buf;
}

bool write_all(const TCHAR* path, const void* data, int size) {
    FILE* fp = std::fopen(w_to_utf8(path).c_str(), "wb");
    if (!fp) return false;
    size_t put = std::fwrite(data, 1, (size_t)size, fp);
    std::fclose(fp);
    return (int)put == size;
}

bool exists(const TCHAR* path) {
    struct stat st;
    return ::stat(w_to_utf8(path).c_str(), &st) == 0;
}

void get_app_data_dir(TCHAR* out_dir) {
    const char* home = getenv("HOME");
    if (!home) {
        struct passwd* pw = getpwuid(getuid());
        home = pw ? pw->pw_dir : ".";
    }
    std::string dir = std::string(home) + "/Library/Application Support/Reader-Mac";
    ::mkdir(dir.c_str(), 0755);
    utf8_to_w(dir.c_str(), out_dir, MAX_PATH);
}

}  // namespace fs
}  // namespace reader

#endif  // !_WIN32

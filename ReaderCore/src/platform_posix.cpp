// POSIX implementation of <tchar.h>-style helpers used by ReaderCore.
// On Windows these are provided by the CRT; we provide reasonable equivalents.

#include "reader/platform.h"

#ifndef _WIN32

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cwchar>
#include <string>

extern "C" int readercore_tcscpy_s(wchar_t* dst, size_t dstsz, const wchar_t* src) {
    if (!dst || dstsz == 0) return -1;
    size_t i = 0;
    if (src) {
        for (; i + 1 < dstsz && src[i]; ++i) {
            dst[i] = src[i];
        }
    }
    dst[i] = 0;
    return 0;
}

extern "C" int readercore_stprintf_s(wchar_t* dst, size_t dstsz, const wchar_t* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int n = std::vswprintf(dst, dstsz, fmt, ap);
    va_end(ap);
    return n;
}

// Convert a wchar_t path (32-bit on macOS) to UTF-8 for fopen.
static std::string wide_to_utf8(const wchar_t* w) {
    std::string out;
    if (!w) return out;
    for (; *w; ++w) {
        uint32_t c = (uint32_t)*w;
        if (c < 0x80) {
            out.push_back((char)c);
        } else if (c < 0x800) {
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

extern "C" FILE* readercore_tfopen(const wchar_t* path, const wchar_t* mode) {
    return std::fopen(wide_to_utf8(path).c_str(), wide_to_utf8(mode).c_str());
}

extern "C" int readercore_ttoi(const wchar_t* s) {
    if (!s) return 0;
    return (int)std::wcstol(s, nullptr, 10);
}

extern "C" long long readercore_ttoi64(const wchar_t* s) {
    if (!s) return 0;
    return (long long)std::wcstoll(s, nullptr, 10);
}

#endif  // !_WIN32

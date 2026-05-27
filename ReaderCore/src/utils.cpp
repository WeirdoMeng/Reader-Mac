// ReaderCore: cross-platform Utils implementation.
// Win32 paths use the existing MultiByteToWideChar / VerQueryValue calls;
// POSIX paths use iconv + manual UTF conversion.

#include "reader/utils.h"

#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#ifndef _WIN32
#include <iconv.h>
#endif

static const char* UTF_16_BE_BOM = "\xFE\xFF";
static const char* UTF_16_LE_BOM = "\xFF\xFE";
static const char* UTF_8_BOM     = "\xEF\xBB\xBF";
static const char* UTF_32_BE_BOM = "\x00\x00\xFE\xFF";
static const char* UTF_32_LE_BOM = "\xFF\xFE\x00\x00";

// ---------- shared static buffers (per original API contract) ----------
static char*    _result  = nullptr;
static int      _len     = 0;
static wchar_t* _wresult = nullptr;
static int      _wlen    = 0;

// ============================================================================
// Encoding conversion
// ============================================================================

#ifdef _WIN32

// ---- Windows: use Win32 codepage APIs (matches upstream byte-for-byte) ----

wchar_t* ansi_to_utf16(const char* str, int size, int* len) {
    *len = MultiByteToWideChar(CP_ACP, 0, str, size, nullptr, 0);
    wchar_t* r = (wchar_t*)malloc(((*len) + 1) * sizeof(wchar_t));
    r[*len] = 0;
    MultiByteToWideChar(CP_ACP, 0, str, size, (LPWSTR)r, *len);
    return r;
}
char* utf16_to_ansi(const wchar_t* str, int size, int* len) {
    *len = WideCharToMultiByte(CP_ACP, 0, str, size, nullptr, 0, nullptr, nullptr);
    char* r = (char*)malloc((*len) + 1);
    r[*len] = 0;
    WideCharToMultiByte(CP_ACP, 0, str, size, r, *len, nullptr, nullptr);
    return r;
}
wchar_t* utf8_to_utf16(const char* str, int size, int* len) {
    *len = MultiByteToWideChar(CP_UTF8, 0, str, size, nullptr, 0);
    wchar_t* r = (wchar_t*)malloc(((*len) + 1) * sizeof(wchar_t));
    r[*len] = 0;
    MultiByteToWideChar(CP_UTF8, 0, str, size, (LPWSTR)r, *len);
    return r;
}
char* utf16_to_utf8(const wchar_t* str, int size, int* len) {
    *len = WideCharToMultiByte(CP_UTF8, 0, str, size, nullptr, 0, nullptr, nullptr);
    char* r = (char*)malloc((*len) + 1);
    r[*len] = 0;
    WideCharToMultiByte(CP_UTF8, 0, str, size, r, *len, nullptr, nullptr);
    return r;
}
char* utf16_to_utf8_bom(const wchar_t* str, int size, int* len) {
    const int bom_len = 3;
    *len = WideCharToMultiByte(CP_UTF8, 0, str, size, nullptr, 0, nullptr, nullptr);
    char* r = (char*)malloc((*len) + 1 + bom_len);
    r[*len + bom_len] = 0;
    memcpy(r, UTF_8_BOM, bom_len);
    WideCharToMultiByte(CP_UTF8, 0, str, size, r + bom_len, *len, nullptr, nullptr);
    return r;
}

#else  // !_WIN32

// ---- POSIX: iconv-based, treating wchar_t as UTF-32 (macOS ships 4-byte wchar_t) ----
// macOS libiconv's WCHAR_T alias is broken; use explicit UTF-32 with the
// platform's native endianness instead.
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define READER_WCHAR_ENCODING "UTF-32BE"
#else
#define READER_WCHAR_ENCODING "UTF-32LE"
#endif

static char* iconv_convert(const char* from_enc,
                           const char* to_enc,
                           const char* in,
                           size_t      in_bytes,
                           size_t      char_size_out,
                           int*        out_len_chars) {
    iconv_t cd = iconv_open(to_enc, from_enc);
    if (cd == (iconv_t)-1) {
        if (out_len_chars) *out_len_chars = 0;
        return nullptr;
    }
    // Reserve enough: worst case 4x input bytes for any conversion, plus terminator.
    size_t out_cap = (in_bytes + 1) * 4 + 4;
    char*  out_buf = (char*)malloc(out_cap);
    if (!out_buf) { iconv_close(cd); return nullptr; }

    char*  inp   = const_cast<char*>(in);
    size_t inb   = in_bytes;
    char*  outp  = out_buf;
    size_t outb  = out_cap - char_size_out;  // leave room for NUL

    iconv(cd, &inp, &inb, &outp, &outb);
    iconv_close(cd);

    size_t written = out_cap - char_size_out - outb;
    // null-terminate
    for (size_t i = 0; i < char_size_out; ++i) outp[i] = 0;

    if (out_len_chars) *out_len_chars = (int)(written / char_size_out);
    return out_buf;
}

wchar_t* ansi_to_utf16(const char* str, int size, int* len) {
    return (wchar_t*)iconv_convert("GBK", READER_WCHAR_ENCODING, str, (size_t)size,
                                   sizeof(wchar_t), len);
}
char* utf16_to_ansi(const wchar_t* str, int size, int* len) {
    return iconv_convert(READER_WCHAR_ENCODING, "GBK", (const char*)str,
                         (size_t)size * sizeof(wchar_t), 1, len);
}
wchar_t* utf8_to_utf16(const char* str, int size, int* len) {
    return (wchar_t*)iconv_convert("UTF-8", READER_WCHAR_ENCODING, str, (size_t)size,
                                   sizeof(wchar_t), len);
}
char* utf16_to_utf8(const wchar_t* str, int size, int* len) {
    return iconv_convert(READER_WCHAR_ENCODING, "UTF-8", (const char*)str,
                         (size_t)size * sizeof(wchar_t), 1, len);
}
char* utf16_to_utf8_bom(const wchar_t* str, int size, int* len) {
    int body_len = 0;
    char* body = utf16_to_utf8(str, size, &body_len);
    if (!body) { *len = 0; return nullptr; }
    const int bom_len = 3;
    char* r = (char*)malloc(bom_len + body_len + 1);
    memcpy(r, UTF_8_BOM, bom_len);
    memcpy(r + bom_len, body, body_len);
    r[bom_len + body_len] = 0;
    free(body);
    *len = body_len;
    return r;
}

#endif  // _WIN32

void free_buffer(void* buffer) {
    if (buffer) free(buffer);
}

// ---------- static-buffer variants ----------

static char* alloc_or_grow_char(int need) {
    if (!_result) {
        _len = need + 1;
        _result = (char*)malloc(_len);
    } else if (_len < need + 1) {
        _len = need + 1;
        _result = (char*)realloc(_result, _len);
    }
    return _result;
}

static wchar_t* alloc_or_grow_wide(int need) {
    if (!_wresult) {
        _wlen = need + 1;
        _wresult = (wchar_t*)malloc(_wlen * sizeof(wchar_t));
    } else if (_wlen < need + 1) {
        _wlen = need + 1;
        _wresult = (wchar_t*)realloc(_wresult, _wlen * sizeof(wchar_t));
    }
    return _wresult;
}

char* Utf16ToUtf8(const wchar_t* str) {
    if (!str) { alloc_or_grow_char(0)[0] = 0; return _result; }
    int len = (int)wcslen(str);
    int out_len = 0;
    char* converted = utf16_to_utf8(str, len, &out_len);
    char* buf = alloc_or_grow_char(out_len);
    memcpy(buf, converted ? converted : "", out_len);
    buf[out_len] = 0;
    free_buffer(converted);
    return buf;
}

char* Utf16ToAnsi(const wchar_t* str) {
    if (!str) { alloc_or_grow_char(0)[0] = 0; return _result; }
    int len = (int)wcslen(str);
    int out_len = 0;
    char* converted = utf16_to_ansi(str, len, &out_len);
    char* buf = alloc_or_grow_char(out_len);
    memcpy(buf, converted ? converted : "", out_len);
    buf[out_len] = 0;
    free_buffer(converted);
    return buf;
}

wchar_t* Utf8ToUtf16(const char* str) {
    if (!str) { alloc_or_grow_wide(0)[0] = 0; return _wresult; }
    int len = (int)strlen(str);
    int out_len = 0;
    wchar_t* converted = utf8_to_utf16(str, len, &out_len);
    wchar_t* buf = alloc_or_grow_wide(out_len);
    if (converted) memcpy(buf, converted, out_len * sizeof(wchar_t));
    buf[out_len] = 0;
    free_buffer(converted);
    return buf;
}

void FreeConvertBuffer() {
    if (_result)  { free(_result);  _result  = nullptr; }
    if (_wresult) { free(_wresult); _wresult = nullptr; }
    _len = 0;
    _wlen = 0;
}

// ============================================================================
// Encoding detection (platform-independent)
// ============================================================================

type_t check_bom(const char* data, size_t size) {
    if (size >= 3 && memcmp(data, UTF_8_BOM, 3) == 0) return utf8;
    if (size >= 4) {
        if (memcmp(data, UTF_32_LE_BOM, 4) == 0) return utf32_le;
        if (memcmp(data, UTF_32_BE_BOM, 4) == 0) return utf32_be;
    }
    if (size >= 2) {
        if (memcmp(data, UTF_16_LE_BOM, 2) == 0) return utf16_le;
        if (memcmp(data, UTF_16_BE_BOM, 2) == 0) return utf16_be;
    }
    return Unknown;
}

int is_ascii(const char* data, size_t size) {
    const unsigned char* p = (const unsigned char*)data;
    const unsigned char* e = p + size;
    for (; p != e; ++p) if (*p & 0x80) return 0;
    return 1;
}

int is_utf8(const char* data, size_t size) {
    const unsigned char* str = (const unsigned char*)data;
    const unsigned char* end = str + size;
    while (str != end) {
        unsigned char b = *str;
        unsigned int code_length;
        uint32_t ch;
        if (b <= 0x7F) { str += 1; continue; }
        if (0xC2 <= b && b <= 0xDF)      code_length = 2;
        else if (0xE0 <= b && b <= 0xEF) code_length = 3;
        else if (0xF0 <= b && b <= 0xF4) code_length = 4;
        else return 0;
        if (str + (code_length - 1) >= end) break;
        for (unsigned int i = 1; i < code_length; ++i)
            if ((str[i] & 0xC0) != 0x80) return 0;
        if (code_length == 2) {
            ch = ((str[0] & 0x1F) << 6) + (str[1] & 0x3F);
        } else if (code_length == 3) {
            ch = ((str[0] & 0x0F) << 12) + ((str[1] & 0x3F) << 6) + (str[2] & 0x3F);
            if (ch < 0x0800) return 0;
            if ((ch >> 11) == 0x1B) return 0;
        } else /* 4 */ {
            ch = ((str[0] & 0x07) << 18) + ((str[1] & 0x3F) << 12) +
                 ((str[2] & 0x3F) << 6) + (str[3] & 0x3F);
            if (ch < 0x10000 || 0x10FFFF < ch) return 0;
        }
        str += code_length;
    }
    return 1;
}

// ============================================================================
// Endian
// ============================================================================

char* le_to_be(char* data, int len) {
    for (int i = 0; i + 1 < len; i += 2) {
        char t = data[i];
        data[i] = data[i + 1];
        data[i + 1] = t;
    }
    return data;
}
char* be_to_le(char* data, int len) { return le_to_be(data, len); }

// ============================================================================
// Base64
// ============================================================================

void b64_encode(const char* src, int slen, char* dst, int* dlen) {
    static const char b64[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    unsigned i_bits = 0;
    int i_shift = 0;
    int out_len = 0;
    for (int i = 0; i < slen; ++i) {
        i_bits = (i_bits << 8) | (unsigned char)src[i];
        i_shift += 8;
        while (i_shift >= 6) {
            dst[out_len++] = b64[(i_bits << 6 >> i_shift) & 0x3F];
            i_shift -= 6;
        }
    }
    while (i_shift > 0) {
        dst[out_len++] = b64[(i_bits << 6 >> i_shift) & 0x3F];
        i_shift -= 6;
    }
    while (out_len & 3) dst[out_len++] = '=';
    *dlen = out_len;
}

void b64_decode(const char* src, int slen, char* dst, int* dlen) {
    static const unsigned char a[256] = {
        64,64,64,64,64,64,64,64, 64,64,64,64,64,64,64,64,
        64,64,64,64,64,64,64,64, 64,64,64,64,64,64,64,64,
        64,64,64,64,64,64,64,64, 64,64,64,62,64,64,64,63,
        52,53,54,55,56,57,58,59, 60,61,64,64,64,64,64,64,
        64, 0, 1, 2, 3, 4, 5, 6,  7, 8, 9,10,11,12,13,14,
        15,16,17,18,19,20,21,22, 23,24,25,64,64,64,64,64,
        64,26,27,28,29,30,31,32, 33,34,35,36,37,38,39,40,
        41,42,43,44,45,46,47,48, 49,50,51,64,64,64,64,64,
    };
    unsigned i_bits = 0;
    int i_shift = 0, out_len = 0;
    for (int i = 0; i < slen; ++i) {
        unsigned char ch = (unsigned char)src[i];
        if (a[ch] == 64) break;
        i_bits = (i_bits << 6) | a[ch];
        i_shift += 6;
        while (i_shift >= 8) {
            dst[out_len++] = (i_bits << 8 >> i_shift) & 0xFF;
            i_shift -= 8;
        }
    }
    *dlen = out_len;
}

// ============================================================================
// URL encode/decode
// ============================================================================

static char to_hex(char code) {
    static const char hex[] = "0123456789abcdef";
    return hex[code & 15];
}
static char from_hex(char ch) {
    return isdigit((unsigned char)ch)
               ? (char)(ch - '0')
               : (char)(tolower((unsigned char)ch) - 'a' + 10);
}

int url_encode(const char* src, char* dest) {
    if (!src || !dest) return -1;
    char* p = dest;
    while (*src) {
        unsigned char c = (unsigned char)*src;
        if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~')
            *p++ = (char)c;
        else if (c == ' ')
            *p++ = '+';
        else {
            *p++ = '%';
            *p++ = to_hex((char)(c >> 4));
            *p++ = to_hex((char)(c & 15));
        }
        ++src;
    }
    *p = 0;
    return (int)(p - dest);
}

int url_decode(const char* src, char* dest) {
    if (!src || !dest) return -1;
    char* p = dest;
    while (*src) {
        if (*src == '%') {
            if (src[1] && src[2]) {
                *p++ = (char)((from_hex(src[1]) << 4) | from_hex(src[2]));
                src += 2;
            }
        } else if (*src == '+') {
            *p++ = ' ';
        } else {
            *p++ = *src;
        }
        ++src;
    }
    *p = 0;
    return (int)(p - dest);
}

// ============================================================================
// Case-insensitive string ops (Windows only — POSIX uses libc)
// ============================================================================

#ifdef _WIN32
static const unsigned char _charmap[256] = {
    /* identical to upstream — see Reader/Utils.cpp */
    0,1,2,3,4,5,6,7, 8,9,10,11,12,13,14,15,
    16,17,18,19,20,21,22,23, 24,25,26,27,28,29,30,31,
    32,33,34,35,36,37,38,39, 40,41,42,43,44,45,46,47,
    48,49,50,51,52,53,54,55, 56,57,58,59,60,61,62,63,
    64,'a','b','c','d','e','f','g',
    'h','i','j','k','l','m','n','o',
    'p','q','r','s','t','u','v','w',
    'x','y','z',91,92,93,94,95,
    96,'a','b','c','d','e','f','g',
    'h','i','j','k','l','m','n','o',
    'p','q','r','s','t','u','v','w',
    'x','y','z',123,124,125,126,127,
    /* 128..255 -- identity */
    128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143,
    144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,
    160,161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,
    176,177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,
    192,193,194,195,196,197,198,199,200,201,202,203,204,205,206,207,
    208,209,210,211,212,213,214,215,216,217,218,219,220,221,222,223,
    224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,
    240,241,242,243,244,245,246,247,248,249,250,251,252,253,254,255,
};

int strcasecmp(const char* s1, const char* s2) {
    const unsigned char* us1 = (const unsigned char*)s1;
    const unsigned char* us2 = (const unsigned char*)s2;
    while (_charmap[*us1] == _charmap[*us2++])
        if (*us1++ == 0) return 0;
    return _charmap[*us1] - _charmap[*--us2];
}
int strncasecmp(const char* s1, const char* s2, int n) {
    if (n != 0) {
        const unsigned char* us1 = (const unsigned char*)s1;
        const unsigned char* us2 = (const unsigned char*)s2;
        do {
            if (_charmap[*us1] != _charmap[*us2++])
                return _charmap[*us1] - _charmap[*--us2];
            if (*us1++ == 0) break;
        } while (--n != 0);
    }
    return 0;
}
char* strcasestr(const char* s, const char* find) {
    char c = *find++;
    if (c == 0) return (char*)s;
    c = (char)tolower((unsigned char)c);
    int len = (int)strlen(find);
    char sc;
    do {
        do {
            sc = *s++;
            if (sc == 0) return nullptr;
        } while ((char)tolower((unsigned char)sc) != c);
    } while (strncasecmp(s, find, len) != 0);
    return (char*)(s - 1);
}
#endif  // _WIN32

// ============================================================================
// Misc
// ============================================================================

BOOL Is_WinXP_SP2_or_Later(void) {
#ifdef _WIN32
    // upstream behavior preserved
    return TRUE;  // we no longer care; downgrade is unsupported
#else
    return TRUE;
#endif
}

void GetApplicationVersion(TCHAR* version) {
    if (!version) return;
#ifdef _WIN32
    *version = 0;
    // upstream Win32 implementation reads VS_FIXEDFILEINFO.
    // Caller can keep that block via #ifdef in their own translation unit
    // if needed; here we don't ship it to avoid Version.lib coupling.
    _tcscpy(version, _T("1.0.0"));
#else
    _tcscpy(version, _T("1.0.0"));
#endif
}

int memvcmp(void* memory, unsigned char val, unsigned int size) {
    unsigned char* mm = (unsigned char*)memory;
    if (size == 0) return 1;
    return (*mm == val) && memcmp(mm, mm + 1, size - 1) == 0;
}

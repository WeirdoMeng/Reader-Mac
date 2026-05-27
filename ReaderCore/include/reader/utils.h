// ReaderCore: cross-platform port of Reader/Utils.h.

#pragma once

#include "reader/platform.h"
#include "reader/types.h"

#include <cstddef>

// ---------- encoding conversion ----------
// "ansi" = legacy system code page; on Windows this is CP_ACP (typically
// GBK in zh-CN); on POSIX we treat it as GBK explicitly.
// "utf16" returns a wchar_t* — note on macOS wchar_t is 4 bytes (UTF-32).
// Returned buffers from these *_to_utf16 / *_to_utf8 calls must be freed
// with free_buffer().
wchar_t* ansi_to_utf16(const char* str, int size, int* len);
char*    utf16_to_ansi(const wchar_t* str, int size, int* len);
wchar_t* utf8_to_utf16(const char* str, int size, int* len);
char*    utf16_to_utf8(const wchar_t* str, int size, int* len);
char*    utf16_to_utf8_bom(const wchar_t* str, int size, int* len);
void     free_buffer(void* buffer);

// Static-buffer convenience variants (caller must NOT free; FreeConvertBuffer()
// is called at app shutdown to release them).
char*    Utf16ToUtf8(const wchar_t* str);
char*    Utf16ToAnsi(const wchar_t* str);
wchar_t* Utf8ToUtf16(const char* str);
void     FreeConvertBuffer();

// ---------- encoding detection ----------
type_t check_bom(const char* data, size_t size);
int    is_ascii(const char* data, size_t size);
int    is_utf8(const char* data, size_t size);

// ---------- endian flip (UTF-16 LE <-> BE in place) ----------
char* le_to_be(char* data, int len);
char* be_to_le(char* data, int len);

// ---------- base64 ----------
void b64_encode(const char* src, int slen, char* dst, int* dlen);
void b64_decode(const char* src, int slen, char* dst, int* dlen);

// ---------- url ----------
int url_encode(const char* src, char* dest);
int url_decode(const char* src, char* dest);

// ---------- case-insensitive string ops ----------
// On POSIX these names exist in <strings.h>, so we wrap them differently.
#ifdef _WIN32
int   strcasecmp(const char* s1, const char* s2);
int   strncasecmp(const char* s1, const char* s2, int n);
char* strcasestr(const char* s, const char* find);
#else
#include <strings.h>
// strcasestr is a GNU extension; macOS ships it in <string.h>. Forward decl
// in case some header path doesn't pull it in.
#ifdef __cplusplus
extern "C" {
#endif
char* strcasestr(const char* s, const char* find);
#ifdef __cplusplus
}
#endif
#endif

// ---------- misc ----------
BOOL Is_WinXP_SP2_or_Later(void);            // POSIX: always TRUE
void GetApplicationVersion(TCHAR* version);  // fills _T("1.0.0") on POSIX
int  memvcmp(void* memory, unsigned char val, unsigned int size);

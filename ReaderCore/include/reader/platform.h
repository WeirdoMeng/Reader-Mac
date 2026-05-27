// ReaderCore platform compatibility header.
// Goal: make original Win32-flavored types/macros compile on macOS/Linux
// with minimal source changes. UI-specific Win32 handles (HWND/HFONT/HDC)
// are NOT defined here — they belong to the UI layer.

#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

#ifdef _WIN32

#include <windows.h>
#include <tchar.h>

#else  // POSIX / macOS

#include <wchar.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---------- primitive types ----------
// Objective-C already provides BOOL via objc/objc.h (signed char or bool).
// Skip redefining when compiling Objective-C(++); the engine treats BOOL as
// "anything that auto-converts to int", which is compatible.
#ifndef OBJC_BOOL_DEFINED
typedef int                BOOL;
#endif
typedef uint8_t            BYTE;
typedef uint16_t           WORD;
typedef uint32_t           DWORD;
typedef int32_t            LONG;
typedef uint32_t           ULONG;
typedef unsigned int       UINT;
typedef int64_t            LONGLONG;
typedef uint64_t           ULONGLONG;
typedef intptr_t           INT_PTR;
typedef uintptr_t          UINT_PTR;

typedef wchar_t            WCHAR;
typedef wchar_t            TCHAR;
typedef const wchar_t*     LPCTSTR;
typedef wchar_t*           LPTSTR;
typedef const wchar_t*     LPCWSTR;
typedef wchar_t*           LPWSTR;
typedef const char*        LPCSTR;
typedef char*              LPSTR;

#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

#ifndef NULL
#define NULL ((void*)0)
#endif

#ifndef MAX_PATH
#define MAX_PATH 1024
#endif

// ---------- string literal & wide-char API shims ----------
#define _T(x)       L##x
#define TEXT(x)     L##x

// strict equivalents to <tchar.h>
#define _tcslen     wcslen
#define _tcscpy     wcscpy
#define _tcscpy_s   readercore_tcscpy_s
#define _tcsncpy    wcsncpy
#define _tcscat     wcscat
#define _tcscmp     wcscmp
#define _tcsicmp    wcscasecmp
#define _tcsncmp    wcsncmp
#define _tcsstr     wcsstr
#define _tcschr     wcschr
#define _tcsrchr    wcsrchr
#define _stprintf   swprintf
#define _stprintf_s readercore_stprintf_s
#define _tprintf    wprintf
#define _tfopen     readercore_tfopen
#define _ttoi       readercore_ttoi
#define _ttoi64     readercore_ttoi64

// safe variants approximation
int  readercore_tcscpy_s(wchar_t* dst, size_t dstsz, const wchar_t* src);
int  readercore_stprintf_s(wchar_t* dst, size_t dstsz, const wchar_t* fmt, ...);
FILE* readercore_tfopen(const wchar_t* path, const wchar_t* mode);
int  readercore_ttoi(const wchar_t* s);
long long readercore_ttoi64(const wchar_t* s);

// ---------- geometric / window placement (struct only, no HWND) ----------
typedef struct tagRECT {
    LONG left;
    LONG top;
    LONG right;
    LONG bottom;
} RECT;

typedef struct tagPOINT {
    LONG x;
    LONG y;
} POINT;

typedef struct tagSIZE {
    LONG cx;
    LONG cy;
} SIZE;

// LOGFONT subset — only what business logic touches. UI layer translates this
// into NSFont / CTFontRef.
#ifndef LF_FACESIZE
#define LF_FACESIZE 32
#endif

typedef struct tagLOGFONTW {
    LONG  lfHeight;
    LONG  lfWidth;
    LONG  lfEscapement;
    LONG  lfOrientation;
    LONG  lfWeight;
    BYTE  lfItalic;
    BYTE  lfUnderline;
    BYTE  lfStrikeOut;
    BYTE  lfCharSet;
    BYTE  lfOutPrecision;
    BYTE  lfClipPrecision;
    BYTE  lfQuality;
    BYTE  lfPitchAndFamily;
    WCHAR lfFaceName[LF_FACESIZE];
} LOGFONTW;
typedef LOGFONTW LOGFONT;

// Window placement — only the geometry fields business logic looks at
// (Win32's full WINDOWPLACEMENT carries SW_SHOWNORMAL etc; on macOS the UI
// layer manages those, so we keep just the frame.)
typedef struct tagWINDOWPLACEMENT {
    UINT  length;
    UINT  flags;
    UINT  showCmd;
    POINT ptMinPosition;
    POINT ptMaxPosition;
    RECT  rcNormalPosition;
} WINDOWPLACEMENT;

// FONT WEIGHT constants
#ifndef FW_NORMAL
#define FW_NORMAL 400
#define FW_BOLD   700
#endif

// ---------- macro/keyword shims ----------
#define __stdcall
#define __cdecl
#define WINAPI
#define CALLBACK
#define APIENTRY

#define _countof(arr)   (sizeof(arr) / sizeof((arr)[0]))
#define ARRAYSIZE(arr)  _countof(arr)

// MAKEWORD / LOWORD / HIWORD
#ifndef MAKEWORD
#define MAKEWORD(a, b)  ((WORD)(((BYTE)((a) & 0xff)) | (((WORD)((BYTE)((b) & 0xff))) << 8)))
#endif
#ifndef LOWORD
#define LOWORD(l)       ((WORD)(((DWORD)(l)) & 0xffff))
#endif
#ifndef HIWORD
#define HIWORD(l)       ((WORD)((((DWORD)(l)) >> 16) & 0xffff))
#endif
#ifndef LOBYTE
#define LOBYTE(w)       ((BYTE)(((WORD)(w)) & 0xff))
#endif
#ifndef HIBYTE
#define HIBYTE(w)       ((BYTE)((((WORD)(w)) >> 8) & 0xff))
#endif

// RGB color packing (Windows: 0x00BBGGRR)
#ifndef RGB
#define RGB(r,g,b) ((DWORD)((BYTE)(r) | ((WORD)((BYTE)(g))<<8) | (((DWORD)(BYTE)(b))<<16)))
#endif
#ifndef GetRValue
#define GetRValue(c)  ((BYTE)((c) & 0xff))
#define GetGValue(c)  ((BYTE)(((c) >> 8) & 0xff))
#define GetBValue(c)  ((BYTE)(((c) >> 16) & 0xff))
#endif

#ifdef __cplusplus
} // extern "C"
#endif

#endif  // _WIN32

// ---------- ASSERT (cross-platform) ----------
#if defined(_DEBUG) || !defined(NDEBUG)
#include <cassert>
#ifndef ASSERT
#define ASSERT(x) assert(x)
#endif
#else
#ifndef ASSERT
#define ASSERT(x)
#endif
#endif

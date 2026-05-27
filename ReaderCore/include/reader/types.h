// ReaderCore: cross-platform port of original Reader/types.h.
// All Win32 *UI* constants (IDM_*, WM_*, HMENU, HWND fields) were removed.
// Only the data shapes the business core needs remain.

#pragma once

#include "reader/platform.h"

#define CACHE_FILE_NAME             _T(".cache.dat")
#define ONLINE_FILE_SAVE_PATH       _T(".online/")

#define DEFAULT_APP_WIDTH           (300)
#define DEFAULT_APP_HEIGHT          (500)

#define ENABLE_TAG                  0
#define ENABLE_REALTIME_SAVE        1
#define ENABLE_GLOBAL_SEARCH        1
#define ENABLE_GLOBAL_KEY           0

#define MAX_CHAPTER_LENGTH          256
#define MAX_MARK_COUNT              256
#define MAX_TAG_COUNT               256
#define MAX_BOOKSRC_COUNT           64
#define MAX_CUST_COLOR_COUNT        16
#define MAX_KEYSET_COUNT            32

typedef unsigned char       u8;
typedef unsigned int        u32;
typedef unsigned long long  u64;

// ---------- per-book persistent item (kept binary-compatible with Win when possible) ----------
typedef struct item_t {
    int   id;
    int   index;                       // current text position
    TCHAR file_name[MAX_PATH];
    int   mark_size;
    int   mark[MAX_MARK_COUNT];        // bookmarks
    int   is_new;
} item_t;

typedef enum bg_image_mode_t {
    Stretch,
    Tile,
    TileFlip
} bg_image_mode_t;

typedef enum auto_page_mode_t {
    apm_page  = 0x00,
    apm_line  = 0x01,
    apm_fixed = 0x00,
    apm_count = 0x10
} auto_page_mode_t;

typedef enum wheel_speed_t {
    ws_single_line = 0,
    ws_double_line,
    ws_three_line,
    ws_fullpage
} wheel_speed_t;

typedef struct bg_image_t {
    BOOL  enable;
    TCHAR file_name[MAX_PATH];
    int   mode;                        // bg_image_mode_t
} bg_image_t;

typedef struct proxy_t {
    BOOL  enable;
    WCHAR addr[64];
    int   port;
    WCHAR user[64];
    WCHAR pass[64];
} proxy_t;

typedef struct chapter_rule_t {
    int   rule;                        // 0: default, 1: keyword, 2: regex
    WCHAR keyword[256];
    WCHAR regex[256];
} chapter_rule_t;

typedef struct book_source_t {
    TCHAR title[256];
    char  host[1024];
    char  query_url[1024];
    int   query_method;
    char  query_params[1024];
    int   query_charset;

    char  book_name_xpath[1024];
    char  book_mainpage_xpath[1024];
    char  book_author_xpath[1024];

    int   enable_chapter_page;
    char  chapter_page_xpath[1024];

    char  chapter_title_xpath[1024];
    char  chapter_url_xpath[1024];
    int   enable_chapter_next;
    char  chapter_next_url_xpath[1024];
    char  chapter_next_keyword_xpath[1024];
    char  chapter_next_keyword[256];

    char  content_xpath[1024];
    int   enable_content_next;
    char  content_next_url_xpath[1024];
    char  content_next_keyword_xpath[1024];
    char  content_next_keyword[256];
    int   content_filter_type;
    wchar_t content_filter_keyword[1024];
} book_source_t;

typedef struct keyset_t {
    DWORD value;
    int   is_disable;
} keyset_t;

// header_t — settings persisted in .cache.dat header.
// NOTE: WINDOWPLACEMENT/LOGFONT/RECT here are the *struct shape* from platform.h,
// not the live Win32 handles. UI layer translates them.
typedef struct header_t {
    TCHAR           version[16];
    int             item_count;
    int             item_id;
    WINDOWPLACEMENT placement;
    WINDOWPLACEMENT fs_placement;
    RECT            fs_rect;
    DWORD           style;
    DWORD           exstyle;
    DWORD           fs_style;
    DWORD           fs_exstyle;
    LOGFONT         font;
    u32             font_color;
    LOGFONT         font_title;
    u32             font_color_title;
    int             use_same_font;
    u32             bg_color;
    BYTE            alpha;
    int             char_gap;
    int             line_gap;
    int             paragraph_gap;
    int             left_line_count;
    RECT            internal_border;
    int             wheel_speed;
    int             page_mode;
    int             autopage_mode;
    bg_image_t      bg_image;
    UINT            uElapse;
    proxy_t         proxy;
    TCHAR           ingore_version[16];
    u32             checkver_time;
    int             hide_taskbar;
    int             show_systray;
    int             disable_lrhide;
    int             disable_eschide;
    int             word_wrap;
    int             line_indent;
    int             blank_lines;
    int             chapter_page;
    int             global_key;
    keyset_t        keyset[MAX_KEYSET_COUNT];
    chapter_rule_t  chapter_rule;
    u32             cust_colors[MAX_CUST_COLOR_COUNT];
    int             meun_font_follow;
    int             book_source_count;
    book_source_t   book_sources[MAX_BOOKSRC_COUNT];
} header_t;

typedef struct body_t {
    item_t items[1];
} body_t;

typedef enum type_t {
    Unknown = 0,
    utf8,
    utf16_le,
    utf16_be,
    utf32_le,
    utf32_be
} type_t;

typedef enum display_status_t {
    ds_normal = 0,
    ds_borderless,
    ds_fullscreen
} display_status_t;

typedef struct ol_chapter_info_t {
    u32 index;
    u32 title_offset;
    u32 url_offset;
    u32 size;
} ol_chapter_info_t;

typedef struct ol_header_t {
    u32 header_size;
    u32 book_name_offset;
    u32 main_page_offset;
    u32 host_offset;
    u64 update_time;
    u32 is_finished;
    u32 reserve[4];
    u32 chapter_size;
    ol_chapter_info_t chapter_info_list[1];
} ol_header_t;

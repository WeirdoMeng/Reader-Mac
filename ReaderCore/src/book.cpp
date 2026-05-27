// ReaderCore: cross-platform Book base class implementation.

#include "reader/book.h"
#include "reader/utils.h"

#include <chrono>
#include <cstdlib>
#include <cstring>

#define MAX_BLANK_LINE 2

Book::Book()
    : m_Data(nullptr)
    , m_Size(0)
    , m_bForceKill(false)
    , m_IsLoading(false)
    , m_Rule(nullptr) {
    std::memset(m_fileName, 0, sizeof(m_fileName));
    m_Chapters.clear();
}

Book::~Book() {
    ForceKill();
    CloseBook();
}

BOOL Book::OpenBook(void) {
    ForceKill();
    m_bForceKill = false;
    m_IsLoading  = true;
    m_Thread = std::thread([this]() {
        BOOL ok = ParserBook();
        m_IsLoading = false;
        if (m_listener && !m_bForceKill.load()) {
            m_listener->on_book_event(reader::BookEvent::OpenFinished, ok ? 1 : 0);
        }
    });
    return TRUE;
}

BOOL Book::OpenBook(char* data, int size) {
    m_Data = data;
    m_Size = size;
    ForceKill();
    m_bForceKill = false;
    m_IsLoading  = true;
    m_Thread = std::thread([this]() {
        BOOL ok = ParserBook();
        m_IsLoading = false;
        if (m_listener && !m_bForceKill.load()) {
            m_listener->on_book_event(reader::BookEvent::OpenFinished, ok ? 1 : 0);
        }
    });
    return TRUE;
}

BOOL Book::CloseBook(void) {
    if (m_Text) { std::free(m_Text); m_Text = nullptr; }
    m_Length = 0;
    m_Chapters.clear();
    std::memset(m_fileName, 0, sizeof(m_fileName));
    if (m_Data) { std::free(m_Data); m_Data = nullptr; }
    m_Size = 0;
    return TRUE;
}

BOOL Book::IsLoading(void) {
    return m_IsLoading.load() ? TRUE : FALSE;
}

wchar_t* Book::GetText(void) {
    return m_Text;
}

void Book::SetFileName(const TCHAR* fileName) {
    _tcscpy(m_fileName, fileName);
}

TCHAR* Book::GetFileName(void) {
    return m_fileName;
}

int Book::GetTextLength(void) {
    return m_Length;
}

chapters_t* Book::GetChapters(void) {
    return &m_Chapters;
}

void Book::SetChapterRule(chapter_rule_t* rule) {
    m_Rule = rule;
}

void Book::JumpChapter(int index) {
    if (IsValid() && index >= 0 && index < (int)m_Chapters.size()) {
        m_Index = m_Chapters[index].index;
        NotifyRedraw();
    }
}

void Book::JumpPrevChapter(void) {
    if (IsValid() && !IsFirstPage()) {
        for (auto it = m_Chapters.rbegin(); it != m_Chapters.rend(); ++it) {
            if (it->index < m_Index) {
                m_Index = it->index;
                NotifyRedraw();
                break;
            }
        }
    }
}

void Book::JumpNextChapter(void) {
    if (IsValid() && !IsLastPage()) {
        for (auto it = m_Chapters.begin(); it != m_Chapters.end(); ++it) {
            if (it->index > m_Index) {
                m_Index = it->index;
                NotifyRedraw();
                break;
            }
        }
    }
}

int Book::GetCurChapterIndex(void) {
    int index = -1;
    if (IsValid()) {
        index = 0;
        for (int i = 0; i < (int)m_Chapters.size(); ++i) {
            if (m_Chapters[i].index > m_Index) break;
            index = i;
        }
    }
    return index;
}

BOOL Book::GetChapterTitle(TCHAR* title, int size) {
    if (!IsValid()) return FALSE;
    int index = GetCurChapterIndex();
    if (index >= 0 && index < (int)m_Chapters.size()) {
        std::wcsncpy(title, m_Chapters[index].title.c_str(), (size_t)(size - 1));
        title[size - 1] = 0;
        return TRUE;
    }
    return FALSE;
}

// Expand a UTF-16 (2-byte) byte buffer into a wchar_t (4-byte on macOS) array.
static wchar_t* utf16_bytes_to_wchar(const char* src, int srcsize, int* dstsize) {
    int n = srcsize / 2;
    wchar_t* dst = (wchar_t*)std::malloc(sizeof(wchar_t) * (size_t)(n + 1));
    if (!dst) { *dstsize = 0; return nullptr; }
    const unsigned char* p = (const unsigned char*)src;
    int out = 0;
    for (int i = 0; i + 1 < srcsize; i += 2) {
        uint16_t lo = (uint16_t)(p[i] | (p[i + 1] << 8));
        if (lo >= 0xD800 && lo <= 0xDBFF && i + 3 < srcsize) {
            uint16_t hi = (uint16_t)(p[i + 2] | (p[i + 3] << 8));
            if (hi >= 0xDC00 && hi <= 0xDFFF) {
                uint32_t cp = 0x10000 + (((uint32_t)(lo - 0xD800) << 10) | (uint32_t)(hi - 0xDC00));
                dst[out++] = (wchar_t)cp;
                i += 2;
                continue;
            }
        }
        dst[out++] = (wchar_t)lo;
    }
    dst[out] = 0;
    *dstsize = out;
    return dst;
}

BOOL Book::DecodeText(const char* src, int srcsize, wchar_t** dst, int* dstsize) {
    type_t bom = check_bom(src, srcsize);

    if (bom == utf8) {
        src += 3; srcsize -= 3;
        *dst = utf8_to_utf16(src, srcsize, dstsize);
    } else if (bom == utf16_le) {
        src += 2; srcsize -= 2;
        *dst = utf16_bytes_to_wchar(src, srcsize, dstsize);
    } else if (bom == utf16_be) {
        src += 2; srcsize -= 2;
        // flip endianness in a temp buffer, then decode as LE
        char* tmp = (char*)std::malloc(srcsize);
        std::memcpy(tmp, src, srcsize);
        be_to_le(tmp, srcsize);
        *dst = utf16_bytes_to_wchar(tmp, srcsize, dstsize);
        std::free(tmp);
    } else if (bom == utf32_le || bom == utf32_be) {
        return FALSE;
    } else if (is_utf8(src, srcsize > 4096 ? 4096 : (size_t)srcsize)) {
        *dst = utf8_to_utf16(src, srcsize, dstsize);
    } else {
        *dst = ansi_to_utf16(src, srcsize, dstsize);
    }

    FormatText(*dst, dstsize);
    return TRUE;
}

BOOL Book::IsChapterIndex(int index) {
    for (auto& c : m_Chapters) {
        if (index == c.index) return TRUE;
    }
    return FALSE;
}

BOOL Book::IsChapter(int index) {
    for (auto& c : m_Chapters) {
        if (index >= c.index && index < c.index + (int)c.title_len) return TRUE;
    }
    return FALSE;
}

BOOL Book::GetChapterInfo(int type, int* start, int* length) {
    *start = 0;
    *length = 0;
    if (m_Chapters.empty()) return FALSE;

    int index = GetCurChapterIndex();
    if (index == -1) return FALSE;

    if (type == -1) {
        if (index > 0) --index; else return FALSE;
    } else if (type == 1) {
        if (index + 1 < (int)m_Chapters.size()) ++index; else return FALSE;
    }

    *start  = (index == 0) ? GetTextBeginIndex() : m_Chapters[index].index;
    *length = (index + 1 == (int)m_Chapters.size())
                  ? (m_Length - *start)
                  : (m_Chapters[index + 1].index - *start);
    return TRUE;
}

BOOL Book::IsValid(void) {
    return Page::IsValid() && !IsLoading();
}

BOOL Book::FormatText(wchar_t* p_data, int* p_len) {
    if (!p_data || *p_len <= 0) return FALSE;

    wchar_t* p_src = p_data;
    int src_len = *p_len;
    int dst_len = 0;
    int line_len = 0, lf_len = 0, is_blank_line = 0;
    int prefix_blank_len = 0, suffix_blank_len = 0;
    int blank_line_num = 0;
    int is_first_line = TRUE;

    wchar_t* p_dst = (wchar_t*)std::malloc(sizeof(wchar_t) * (size_t)(src_len + 1));
    if (!p_dst) return FALSE;

    while (GetLine(p_src, src_len - (int)(p_src - p_data),
                   &line_len, &lf_len, &is_blank_line,
                   &prefix_blank_len, &suffix_blank_len)) {
        if (is_blank_line) {
            if (is_first_line || ++blank_line_num >= MAX_BLANK_LINE) {
                p_src += line_len + lf_len;
                continue;
            }
        } else {
            blank_line_num = 0;
        }
        is_first_line = FALSE;

        if (line_len - prefix_blank_len - suffix_blank_len > 0) {
            int body_len = line_len - prefix_blank_len - suffix_blank_len;
            if (prefix_blank_len > 4 && (p_src[0] == 0x20 || p_src[0] == 0xA0)) {
                p_dst[dst_len++] = 0x20;
                p_dst[dst_len++] = 0x20;
                p_dst[dst_len++] = 0x20;
                p_dst[dst_len++] = 0x20;
                std::memcpy(p_dst + dst_len, p_src + prefix_blank_len,
                            sizeof(wchar_t) * (size_t)body_len);
                dst_len += body_len;
            } else if (prefix_blank_len > 2 && p_src[0] == 0x3000) {
                p_dst[dst_len++] = 0x3000;
                p_dst[dst_len++] = 0x3000;
                std::memcpy(p_dst + dst_len, p_src + prefix_blank_len,
                            sizeof(wchar_t) * (size_t)body_len);
                dst_len += body_len;
            } else {
                std::memcpy(p_dst + dst_len, p_src,
                            sizeof(wchar_t) * (size_t)(line_len - suffix_blank_len));
                dst_len += line_len - suffix_blank_len;
            }
        }
        if (lf_len > 0) p_dst[dst_len++] = 0x0A;
        p_src += line_len + lf_len;
    }

    std::memcpy(p_data, p_dst, sizeof(wchar_t) * (size_t)dst_len);
    p_data[dst_len] = 0;
    *p_len = dst_len;
    std::free(p_dst);
    return TRUE;
}

BOOL Book::GetLine(wchar_t* text, int len, int* line_len, int* lf_len,
                   int* is_blank_line, int* prefix_blank_len, int* suffix_blank_len) {
    if (line_len) *line_len = 0;
    if (lf_len) *lf_len = 0;
    if (is_blank_line) *is_blank_line = 1;
    if (prefix_blank_len) *prefix_blank_len = 0;
    if (suffix_blank_len) *suffix_blank_len = 0;
    if (!text || len <= 0) return FALSE;

    int is_prefix = 1, is_suffix = 0;
    for (int i = 0; i < len; ++i) {
        wchar_t c = text[i];
        if (is_blank(c)) {
            if (is_prefix && prefix_blank_len) (*prefix_blank_len)++;
            if (is_suffix && suffix_blank_len) (*suffix_blank_len)++;
        } else if (!IsNewLine(c)) {
            is_prefix = 0;
            is_suffix = 1;
            if (suffix_blank_len) *suffix_blank_len = 0;
            if (is_blank_line) *is_blank_line = 0;
        }
        if (i + 1 < len && c == 0x0D && text[i + 1] == 0x0A) {
            if (line_len) *line_len = i;
            if (lf_len) *lf_len = 2;
            return TRUE;
        }
        if (c == 0x0A) {
            if (line_len) *line_len = i;
            if (lf_len) *lf_len = 1;
            return TRUE;
        }
    }
    if (line_len) *line_len = len;
    if (lf_len) *lf_len = 0;
    return TRUE;
}

void Book::ForceKill(void) {
    if (m_Thread.joinable()) {
        m_bForceKill = true;
        m_Thread.join();           // cooperative; ParserBook polls m_bForceKill
        m_IsLoading  = false;
    }
}

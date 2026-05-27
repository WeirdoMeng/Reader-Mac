// ReaderCore: cross-platform Page implementation.
// See reader/page.h for design notes.

#include "reader/page.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <climits>

#define CHAR_GAP        (m_header->char_gap)
#define LINE_GAP        (m_header->line_gap)
#define PART_GAP        (m_header->paragraph_gap)
#define LEFT_MIN        (m_header->internal_border.left)
#define TOP_MIN         (m_header->internal_border.top)
#define RIGHT_MIN       (m_header->internal_border.right)
#define BOTTOM_MIN      (m_header->internal_border.bottom)
#define NO_BLANS_LINE   (m_header->blank_lines)
#define LINE_INDENT     (m_header->line_indent)
#define WORD_WRAP       (m_header->word_wrap)
#define CHAPTER_PAGE    (m_header->chapter_page)
#define LINE_NUM        (m_header->wheel_speed)
#define LEFT_NUM        (m_header->left_line_count)

Page::Page()
    : m_Text(nullptr)
    , m_Length(0)
    , m_pIndex(nullptr)
    , m_PageLength(0)
    , m_header(nullptr)
    , m_metrics(nullptr)
    , m_listener(nullptr)
    , m_dcIndex(0)
    , m_LineCount(0)
    , m_DrawType(DRAW_NULL)
    , m_BlankPage(TRUE)
    , m_ChapterStart(0)
    , m_ChapterLength(0) {
    std::memset(&m_PageInfo, 0, sizeof(page_info_t));
}

Page::~Page() {
    ReleasePageInfo();
}

void Page::Init(int* p_index, header_t* header) {
    m_pIndex = p_index;
    m_header = header;
    if (m_Index <= 0 || m_Index > m_Length)
        m_Index = 0;
}

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

void Page::PageUp(BOOL draw) {
    if (!OnUpDownEvent(DRAW_PAGE_UP)) return;
    if (draw && !IsValid()) return;
    if (m_Index > 0) {
        m_DrawType = DRAW_PAGE_UP;
        m_LineCount = LEFT_NUM;
        if (draw) NotifyRedraw();
    }
}

void Page::PageDown(BOOL draw) {
    if (!OnUpDownEvent(DRAW_PAGE_DOWN)) return;
    if (draw && !IsValid()) return;
    if (m_Index + m_PageInfo.length < m_Length) {
        m_DrawType = DRAW_PAGE_DOWN;
        m_LineCount = LEFT_NUM;
        if (draw) NotifyRedraw();
    }
}

void Page::LineUp(BOOL draw) {
    if (!OnUpDownEvent(DRAW_LINE_UP)) return;
    if (draw && !IsValid()) return;
    if (m_Index > 0) {
        switch (LINE_NUM) {
            case ws_single_line: m_LineCount = 1; break;
            case ws_double_line: m_LineCount = 2; break;
            case ws_three_line:  m_LineCount = 3; break;
            default:             PageUp(draw); return;
        }
        m_DrawType = DRAW_LINE_UP;
        if (draw) NotifyRedraw();
    }
}

void Page::LineDown(BOOL draw) {
    if (!OnUpDownEvent(DRAW_LINE_DOWN)) return;
    if (draw && !IsValid()) return;
    if (m_Index + m_PageInfo.length < m_Length) {
        switch (LINE_NUM) {
            case ws_single_line: m_LineCount = 1; break;
            case ws_double_line: m_LineCount = 2; break;
            case ws_three_line:  m_LineCount = 3; break;
            default:             PageDown(draw); return;
        }
        m_DrawType = DRAW_LINE_DOWN;
        if (draw) NotifyRedraw();
    }
}

// ---------------------------------------------------------------------------
// Layout entry point (replaces upstream DrawPage)
// ---------------------------------------------------------------------------

void Page::CalcLayout(int width, int height) {
    if (!IsValid() || !m_metrics) return;
    if (!OnDrawPageEvent()) return;

    // "cover page" is handled by the UI layer (page 0 if HasCover()).
    if (m_Index == 0 && HasCover() &&
        (m_DrawType == DRAW_NULL ||
         m_DrawType == DRAW_PAGE_UP || m_DrawType == DRAW_LINE_UP)) {
        m_PageLength = 1;
        m_DrawType   = DRAW_NULL;
        m_LineCount  = 0;
        m_PageInfo.start  = m_Index;
        m_PageInfo.length = 1;
        ClearLines();
        return;
    }

    switch (m_DrawType) {
        case DRAW_NULL:
        case DRAW_PAGE_DOWN:
        case DRAW_LINE_DOWN:
            CalcPageDown(width, height);
            break;
        case DRAW_PAGE_UP:
        case DRAW_LINE_UP:
            CalcPageUp(width, height);
            break;
        default: break;
    }

    m_DrawType  = DRAW_NULL;
    m_LineCount = 0;
    m_Index       = m_PageInfo.start;
    m_PageLength  = m_PageInfo.length;
    m_BlankPage   = (m_PageInfo.lines.used == 0);

    NotifySaveCache();
}

// ---------------------------------------------------------------------------
// Query
// ---------------------------------------------------------------------------

BOOL Page::IsFirstPage(void) const {
    return m_pIndex && m_Index == 0;
}

BOOL Page::IsLastPage(void) const {
    return m_pIndex && (m_Index + m_PageLength == m_Length);
}

BOOL Page::IsCoverPage(void) const {
    return m_pIndex && m_Index == 0 && const_cast<Page*>(this)->HasCover();
}

double Page::GetProgress(void) const {
    return m_Length == 0 ? 0.0 : ((m_Index + m_PageLength) * 100.0 / m_Length);
}

BOOL Page::GetCurPageText(TCHAR** text) const {
    if (m_PageLength <= 0) return FALSE;
    int newlinecount = 0;
    for (int i = 0; i < m_PageLength; ++i) {
        if (m_Text[m_Index + i] == 0x0A) ++newlinecount;
    }
    *text = (TCHAR*)std::malloc(sizeof(TCHAR) * (m_PageLength + newlinecount + 1));
    int j = 0;
    for (int i = 0; i < m_PageLength; ++i) {
        TCHAR c = m_Text[m_Index + i];
        if (c == 0x0A) (*text)[j++] = 0x0D;
        (*text)[j++] = c;
    }
    (*text)[j] = 0;
    return TRUE;
}

// ---------------------------------------------------------------------------
// Font selection (replaces SelectFont/SelectFontByDcIndex)
// ---------------------------------------------------------------------------

int Page::SelectFont(int index, BOOL is_title) {
    int dc_index;
    if (m_header->use_same_font) {
        dc_index = 0;
    } else if (is_title) {
        dc_index = 1;
    } else {
        dc_index = 0;
    }
    if (m_dcIndex != dc_index || index == 0) {
        m_dcIndex = dc_index;
        if (m_metrics) {
            reader::FontDesc fd;
            fd.logfont  = (dc_index == 1) ? &m_header->font_title : &m_header->font;
            fd.is_title = (dc_index == 1);
            m_metrics->use_font(fd);
        }
    }
    return m_dcIndex;
}

void Page::SelectFontByDcIndex(int dc_idx) {
    if (dc_idx >= 0 && dc_idx < 2 && m_dcIndex != dc_idx) {
        m_dcIndex = dc_idx;
        if (m_metrics) {
            reader::FontDesc fd;
            fd.logfont  = (dc_idx == 1) ? &m_header->font_title : &m_header->font;
            fd.is_title = (dc_idx == 1);
            m_metrics->use_font(fd);
        }
    }
}

// ---------------------------------------------------------------------------
// Paragraph boundary scanning (platform-independent, identical to upstream)
// ---------------------------------------------------------------------------

int Page::GetPrevParagraph(int start, int max_len, int* is_blank_out, int* crlf_len) {
    int length = 0;
    int end = start - max_len + 1;
    if (start < 0) return 0;
    if (end < GetTextBeginIndex()) end = GetTextBeginIndex();
    if (CHAPTER_PAGE) {
        if (end < m_ChapterStart) end = m_ChapterStart;
        if (start > m_ChapterStart + m_ChapterLength - 1)
            start = m_ChapterStart + m_ChapterLength - 1;
    }

    *is_blank_out = 1;
    *crlf_len = 0;
    int i;
    for (i = start; i >= end; --i, ++length) {
        if ((i - 1 >= 0 && m_Text[i] == L'\n' && m_Text[i - 1] == L'\r') ||
            m_Text[i] == L'\r' || m_Text[i] == L'\n') {
            if (length == 0) {
                if (i - 1 >= 0 && m_Text[i] == L'\n' && m_Text[i - 1] == L'\r') {
                    --i; ++length; *crlf_len += 1;
                }
                *crlf_len += 1;
                continue;
            }
            break;
        }
        if ((*is_blank_out) && !is_blank(m_Text[i])) *is_blank_out = 0;
    }
    return length;
}

int Page::GetNextParagraph(int start, int max_len, int* is_blank_out, int* crlf_len) {
    int length = 0;
    int end = start + max_len;
    if (start < 0) return 0;
    if (end > m_Length) end = m_Length;

    *is_blank_out = 1;
    *crlf_len = 0;

    if (CHAPTER_PAGE) {
        if (start < m_ChapterStart) start = m_ChapterStart;
        if (end > m_ChapterStart + m_ChapterLength)
            end = m_ChapterStart + m_ChapterLength;
    }

    for (int i = start; i < end; ++i, ++length) {
        if ((i + 1 < end && m_Text[i] == L'\r' && m_Text[i + 1] == L'\n') ||
            m_Text[i] == L'\r' || m_Text[i] == L'\n') {
            if (i + 1 < end && m_Text[i] == L'\r' && m_Text[i + 1] == L'\n') {
                ++i; ++length; *crlf_len += 1;
            }
            ++length; *crlf_len += 1;
            break;
        }
        if ((*is_blank_out) && !is_blank(m_Text[i])) *is_blank_out = 0;
    }
    return length;
}

// ---------------------------------------------------------------------------
// Layout a paragraph into 1..N lines
// ---------------------------------------------------------------------------

int Page::ParagraphToLines(int start, int length, int width, int height, int line_idx) {
    int end = start + length;
    int line_idx_bak = line_idx;
    int is_blank_line = 1;
    int is_new_paragraph = start == 0 ? TRUE : (m_Text[start - 1] == 0x0A ? TRUE : FALSE);
    int is_title = IsChapter(start);
    int indent_width = GetIndentWidth();
    int x, y, w, h;
    int char_start, line_start, word_start;
    int line_len, char_len, word_height;
    int last_cy = 0;  // last measurement, to mimic upstream's sz at loop end
    char_info_t* chars = (char_info_t*)std::malloc(sizeof(char_info_t) * length);

    if (start < 0 || end > m_Length || !chars) {
        if (chars) std::free(chars);
        return 0;
    }

    x = (LINE_INDENT && !is_title && is_new_paragraph) ? indent_width : 0;
    y = 0;
    w = 0;
    h = 0;
    char_start = start;
    word_start = start;
    line_start = start;
    is_blank_line = 1;

    int i;
    for (i = start; i < end; ++i) {
        SelectFont(i, is_title);
        reader::CharMetrics cm = m_metrics->measure_char(m_Text[i]);
        last_cy = cm.line_height;

        chars[i - start].idx    = i;
        chars[i - start].dc_idx = m_dcIndex;
        chars[i - start].cx     = cm.advance_x;
        chars[i - start].cy     = cm.line_height;

        if (i == start && x == indent_width && x + cm.advance_x > width) {
            x = 0;
        }
        if (cm.advance_x > width) {
            break;
        }
        if (y + std::max(h, cm.line_height) > height) {
            break;
        }

        if (x + w + cm.advance_x > width) {
            if (WORD_WRAP) {
                if (is_blank(m_Text[i])) {
                    w += cm.advance_x + CHAR_GAP;
                    word_start = i + 1;
                    continue;
                } else if (word_start != char_start) {
                    // move current word to next line
                    line_len = word_start - line_start;
                    char_len = word_start - char_start;
                    word_height = 0;
                    is_blank_line = 1;
                    for (int j = char_start - start; j < char_start - start + char_len; ++j) {
                        word_height = std::max(word_height, chars[j].cy);
                        if (is_blank_line && !is_blank(m_Text[chars[j].idx]))
                            is_blank_line = 0;
                    }
                    if (word_height == 0) word_height = h;

                    AddCharsToLine(line_idx++, chars, char_start - start, char_len,
                                   line_start, line_len, x, word_height,
                                   is_blank_line ? 0 : LINE_GAP);
                    x = 0;
                    y += word_height + (is_blank_line ? 0 : LINE_GAP);
                    w = 0; h = 0;
                    line_start = word_start;
                    char_start = word_start;
                    is_blank_line = 1;
                    for (int j = word_start - start; j < i - start; ++j) {
                        w += chars[j].cx + CHAR_GAP;
                        h = std::max(h, chars[j].cy);
                        if (is_blank_line && !is_blank(m_Text[chars[j].idx]))
                            is_blank_line = 0;
                    }
                    goto _continue;
                }
            }

            // add line
            AddCharsToLine(line_idx++, chars, char_start - start, i - char_start,
                           line_start, i - line_start, x, h,
                           is_blank_line ? 0 : LINE_GAP);
            x = 0;
            y += h + (is_blank_line ? 0 : LINE_GAP);
            w = 0; h = 0;
            char_start = i;
            word_start = i;
            line_start = i;
            is_blank_line = 1;
        }

    _continue:
        if (is_blank(m_Text[i])) {
            if (LINE_INDENT && char_start == i && !is_title &&
                is_new_paragraph && line_start == start) {
                char_start = i + 1;
                word_start = i + 1;
                h = std::max(h, cm.line_height);
                continue;
            }
            word_start = i + 1;
        } else if (is_hyphen(m_Text[i])) {
            word_start = i + 1;
            is_blank_line = 0;
        } else {
            is_blank_line = 0;
        }
        w += cm.advance_x + CHAR_GAP;
        h = std::max(h, cm.line_height);
    }

    h = std::max(h, last_cy);
    if (i == end && i - line_start > 0 && y + h <= height) {
        AddCharsToLine(line_idx++, chars, char_start - start, i - char_start,
                       line_start, i - line_start, x, h, LINE_GAP);
    }

    std::free(chars);
    return line_idx - line_idx_bak;
}

int Page::AddCharsToLine(int line_idx, char_info_t* chars,
                         int char_start, int char_len,
                         int line_start, int line_len,
                         int x, int cy, int gap) {
    const int LINE_UNIT = 32;
    char_info_t* p_chars;
    lines_t* p_lines = &m_PageInfo.lines;

    if (p_lines->used == p_lines->total) {
        p_lines->total += LINE_UNIT;
        p_lines->lines = (line_info_t*)std::realloc(
            p_lines->lines, sizeof(line_info_t) * p_lines->total);
    }

    if (WORD_WRAP) {
        while (char_len > 0 && is_space(m_Text[(chars + char_start + char_len - 1)->idx])) {
            --char_len;
        }
    }

    if (char_len > 0) {
        p_chars = (char_info_t*)std::malloc(sizeof(char_info_t) * char_len);
        std::memcpy(p_chars, chars + char_start, sizeof(char_info_t) * char_len);
    } else {
        p_chars = nullptr;
    }

    if (line_idx >= 0 && line_idx < p_lines->used) {
        std::memmove(&p_lines->lines[line_idx + 1], &p_lines->lines[line_idx],
                     sizeof(line_info_t) * (p_lines->used - line_idx));
    } else {
        line_idx = p_lines->used;
    }
    p_lines->lines[line_idx].start    = line_start;
    p_lines->lines[line_idx].length   = line_len;
    p_lines->lines[line_idx].x        = x;
    p_lines->lines[line_idx].cy       = cy;
    p_lines->lines[line_idx].gap      = gap;
    p_lines->lines[line_idx].chars    = p_chars;
    p_lines->lines[line_idx].char_cnt = char_len;
    p_lines->used++;
    return 0;
}

void Page::RemoveLines(int line_idx, int count) {
    lines_t* p_lines = &m_PageInfo.lines;
    int used = p_lines->used;
    for (int i = line_idx; i < used && i < line_idx + count; ++i) {
        if (p_lines->lines[i].chars) std::free(p_lines->lines[i].chars);
        p_lines->used--;
    }
    if (line_idx + count < used) {
        std::memmove(&p_lines->lines[line_idx],
                     &p_lines->lines[line_idx + count],
                     sizeof(line_info_t) * (used - line_idx - count));
    }
}

void Page::ClearLines(void) {
    lines_t* p_lines = &m_PageInfo.lines;
    for (int i = 0; i < p_lines->used; ++i) {
        if (p_lines->lines[i].chars) std::free(p_lines->lines[i].chars);
    }
    p_lines->used = 0;
}

void Page::ReleasePageInfo(void) {
    lines_t* p_lines = &m_PageInfo.lines;
    for (int i = 0; i < p_lines->used; ++i) {
        if (p_lines->lines[i].chars) std::free(p_lines->lines[i].chars);
    }
    if (p_lines->lines) std::free(p_lines->lines);
    std::memset(&m_PageInfo, 0, sizeof(page_info_t));
}

// ---------------------------------------------------------------------------
// Page calculation
// ---------------------------------------------------------------------------

void Page::CalcPageDown(int rc_width, int rc_height) {
    int width  = rc_width  - LEFT_MIN - RIGHT_MIN;
    int height = rc_height - TOP_MIN  - BOTTOM_MIN;
    int start_pos, length;
    int is_blank_line = 1;
    int remain_blank_length = 0;
    int crlf_len = 0;
    int line_idx = 0;
    int max_page_length = GetMaxPageLength(width, height);
    int h = height, line_cnt;
    line_info_t* p_line;

    if (m_DrawType == DRAW_NULL) {
        ClearLines();
        start_pos = m_Index;
    } else if (m_DrawType == DRAW_PAGE_DOWN) {
        if (m_LineCount > 0 && m_PageInfo.lines.used > 0 && !CHAPTER_PAGE) {
            int cnt = m_LineCount > m_PageInfo.lines.used - 1 ?
                          m_PageInfo.lines.used - 1 : m_LineCount;
            if (m_PageInfo.lines.used - cnt > 0)
                RemoveLines(0, m_PageInfo.lines.used - cnt);
            for (int i = 0; i < m_PageInfo.lines.used; ++i) {
                h -= m_PageInfo.lines.lines[i].cy;
                h -= m_PageInfo.lines.lines[i].gap;
            }
            p_line = &m_PageInfo.lines.lines[m_PageInfo.lines.used - 1];
            start_pos = p_line->start + p_line->length;
        } else {
            ClearLines();
            start_pos = m_Index + m_PageLength;
        }
    } else if (m_DrawType == DRAW_LINE_DOWN) {
        int cnt = m_LineCount > m_PageInfo.lines.used ?
                      m_PageInfo.lines.used : m_LineCount;
        if (cnt < m_PageInfo.lines.used) {
            RemoveLines(0, cnt);
            for (int i = 0; i < m_PageInfo.lines.used; ++i) {
                h -= m_PageInfo.lines.lines[i].cy;
                h -= m_PageInfo.lines.lines[i].gap;
            }
            p_line = &m_PageInfo.lines.lines[m_PageInfo.lines.used - 1];
            start_pos = p_line->start + p_line->length;
        } else {
            ClearLines();
            start_pos = m_Index + m_PageLength;
        }
    } else {
        return;
    }

    if (CHAPTER_PAGE) {
        if (GetChapterInfo(0, &m_ChapterStart, &m_ChapterLength)) {
            if (m_ChapterStart + m_ChapterLength == m_Index + m_PageLength &&
                m_PageInfo.lines.used == 0 && m_DrawType != DRAW_NULL) {
                if (!GetChapterInfo(1, &m_ChapterStart, &m_ChapterLength)) {
                    m_ChapterStart  = GetTextBeginIndex();
                    m_ChapterLength = m_Length - GetTextBeginIndex();
                }
            }
        } else {
            m_ChapterStart  = GetTextBeginIndex();
            m_ChapterLength = m_Length - GetTextBeginIndex();
        }
    }

    line_idx = m_PageInfo.lines.used;
    if (m_PageInfo.lines.used == 0)
        m_PageInfo.start = start_pos;
    else
        m_PageInfo.start = -1;

    while ((length = GetNextParagraph(start_pos, max_page_length, &is_blank_line, &crlf_len)) > 0) {
        if (is_blank_line) {
            if (NO_BLANS_LINE) {
                remain_blank_length += length;
                start_pos += length;
                continue;
            }
            SelectFont(start_pos, FALSE);
            reader::CharMetrics cm = m_metrics->measure_char(m_Text[start_pos]);
            if (h >= cm.line_height) {
                AddCharsToLine(line_idx++, nullptr, 0, 0, start_pos, length, 0, cm.line_height, 0);
                h -= cm.line_height;
                if (h == cm.line_height) break;
            } else {
                break;
            }
            remain_blank_length = 0;
        } else {
            remain_blank_length = 0;
            line_cnt = ParagraphToLines(start_pos, length - crlf_len, width, h, line_idx);
            if (line_cnt == 0) break;
            p_line = &m_PageInfo.lines.lines[m_PageInfo.lines.used - 1];
            if (p_line->start + p_line->length == start_pos + length - crlf_len) {
                if (crlf_len) {
                    p_line->gap     = PART_GAP;
                    p_line->length += crlf_len;
                }
            } else {
                break;
            }
        }

        h = height;
        for (int i = 0; i < m_PageInfo.lines.used; ++i) {
            h -= m_PageInfo.lines.lines[i].cy;
            h -= m_PageInfo.lines.lines[i].gap;
        }
        start_pos += length;
        line_idx = m_PageInfo.lines.used;
    }

    if (m_PageInfo.lines.used > 0) {
        p_line = &m_PageInfo.lines.lines[m_PageInfo.lines.used - 1];
        if (m_PageInfo.start == -1 || m_PageInfo.start > m_PageInfo.lines.lines[0].start)
            m_PageInfo.start = m_PageInfo.lines.lines[0].start;
        m_PageInfo.length = p_line->start + p_line->length -
                            m_PageInfo.start + remain_blank_length;
    } else {
        m_PageInfo.start  = m_Index + m_PageLength;
        m_PageInfo.length = 0;
    }
}

void Page::CalcPageUp(int rc_width, int rc_height) {
    int width  = rc_width  - LEFT_MIN - RIGHT_MIN;
    int height = rc_height - TOP_MIN  - BOTTOM_MIN;
    int start_pos, length;
    int is_blank_line = 1;
    int check_remain_blank = 1;
    int remain_blank_length = 0;
    int check_not_enough = 1;
    int crlf_len = 0;
    int line_idx = 0;
    int max_page_length = GetMaxPageLength(width, height);
    int line_cnt = 0, h, idx = -1;
    line_info_t* p_line;

    if (m_Index <= GetTextBeginIndex()) return;

    int cnt_up = 0;
    if (m_DrawType == DRAW_PAGE_UP) {
        if (m_LineCount > 0 && m_PageInfo.lines.used > 0 && !CHAPTER_PAGE) {
            int cnt = m_LineCount > m_PageInfo.lines.used - 1 ?
                          m_PageInfo.lines.used - 1 : m_LineCount;
            if (m_PageInfo.lines.used - cnt > 0)
                RemoveLines(cnt, m_PageInfo.lines.used - cnt);
        } else {
            ClearLines();
        }
    } else if (m_DrawType == DRAW_LINE_UP) {
        cnt_up = -m_LineCount;
    } else {
        return;
    }

    if (CHAPTER_PAGE) {
        if (GetChapterInfo(0, &m_ChapterStart, &m_ChapterLength)) {
            if (m_ChapterStart == m_Index) {
                if (GetChapterInfo(-1, &m_ChapterStart, &m_ChapterLength)) {
                    ClearLines();
                } else {
                    m_ChapterStart  = GetTextBeginIndex();
                    m_ChapterLength = m_Length - GetTextBeginIndex();
                }
            }
        } else {
            m_ChapterStart  = GetTextBeginIndex();
            m_ChapterLength = m_Length - GetTextBeginIndex();
        }
    }

    start_pos = m_Index - 1;
    line_idx = 0;
    m_PageInfo.start = -1;

    while ((length = GetPrevParagraph(start_pos, max_page_length, &is_blank_line, &crlf_len)) > 0) {
        if (is_blank_line) {
            if (NO_BLANS_LINE) {
                m_PageInfo.start = start_pos - length + 1;
                start_pos -= length;
                if (m_PageInfo.lines.used == 0) remain_blank_length += length;
                continue;
            }
            SelectFont(start_pos, FALSE);
            reader::CharMetrics cm = m_metrics->measure_char(m_Text[start_pos - length + 1]);
            AddCharsToLine(line_idx, nullptr, 0, 0,
                           start_pos - length + 1, length, 0, cm.line_height, 0);
            line_cnt = 1;
        } else {
            line_cnt = ParagraphToLines(start_pos - length + 1, length - crlf_len,
                                        width, INT_MAX, line_idx);
            if (line_cnt == 0) {
                check_remain_blank = 0;
                check_not_enough = 0;
                ClearLines();
                break;
            }
            p_line = &m_PageInfo.lines.lines[line_idx + line_cnt - 1];
            if (crlf_len > 0) {
                p_line->gap     = PART_GAP;
                p_line->length += crlf_len;
            }
        }

        if (m_DrawType == DRAW_LINE_UP) {
            cnt_up += line_cnt;
            if (cnt_up >= 0) {
                if (cnt_up > 0) {
                    p_line = &m_PageInfo.lines.lines[line_idx + line_cnt - 1];
                    RemoveLines(0, cnt_up);
                    check_remain_blank = 0;
                }
                idx = -1; h = 0;
                for (int i = 0; i < m_PageInfo.lines.used; ++i) {
                    h += m_PageInfo.lines.lines[i].cy;
                    if (h > height) { idx = i; break; }
                    h += m_PageInfo.lines.lines[i].gap;
                }
                if (idx != -1) {
                    RemoveLines(idx, m_PageInfo.lines.used - idx);
                    check_not_enough = 0;
                }
                break;
            }
        } else {
            h = 0; idx = -1;
            for (int i = m_PageInfo.lines.used - 1; i >= 0; --i) {
                h += m_PageInfo.lines.lines[i].cy;
                if (h > height) { idx = i + 1; break; }
                if (i > 0) h += m_PageInfo.lines.lines[i - 1].gap;
            }
            if (idx != -1) {
                RemoveLines(0, idx);
                check_not_enough = 0;
                break;
            }
        }
        start_pos -= length;
    }

    if (m_PageInfo.lines.used > 0) {
        p_line = &m_PageInfo.lines.lines[m_PageInfo.lines.used - 1];
        if (m_PageInfo.start == -1 || m_PageInfo.start > m_PageInfo.lines.lines[0].start)
            m_PageInfo.start = m_PageInfo.lines.lines[0].start;
        m_PageInfo.length = p_line->start + p_line->length -
                            m_PageInfo.start + remain_blank_length;
    } else {
        m_PageInfo.start  = m_Index;
        m_PageInfo.length = 0;
        return;
    }

    if (NO_BLANS_LINE && check_remain_blank && m_PageInfo.lines.used > 0) {
        start_pos = m_PageInfo.start - 1;
        is_blank_line = 1;
        while (start_pos >= GetTextBeginIndex() && is_blank_line &&
               (length = GetPrevParagraph(start_pos, max_page_length,
                                          &is_blank_line, &crlf_len)) > 0) {
            if (is_blank_line) {
                m_PageInfo.length += length;
                m_PageInfo.start  -= length;
                start_pos         -= length;
            }
        }
    }

    if (check_not_enough && m_PageInfo.lines.used > 0) {
        m_Index     = m_PageInfo.start;
        m_DrawType  = DRAW_NULL;
        m_LineCount = 0;
        CalcPageDown(rc_width, rc_height);
    }
}

int Page::GetMaxPageLength(int w, int h) {
    SelectFontByDcIndex(0);
    reader::CharMetrics cm = m_metrics->measure_char(L'i');
    int cx = cm.advance_x ? cm.advance_x : 1;
    int cy = cm.line_height ? cm.line_height : 1;
    int wcnt = w / (cx + CHAR_GAP);
    int hcnt = h / (cy + LINE_GAP);
    return ((wcnt * hcnt) + 1023) / 1024 * 1024;
}

int Page::GetIndentWidth(void) {
    SelectFontByDcIndex(0);
    return m_metrics->indent_width();
}

// ---------------------------------------------------------------------------
// Predicates
// ---------------------------------------------------------------------------

BOOL Page::IsCover(int index) {
    return index == 0 && HasCover();
}
BOOL Page::IsTitle(int index) {
    return IsChapterIndex(index);
}
BOOL Page::IsNewLine(wchar_t c) {
    return c == 0x0A || c == 0x0D;
}
BOOL Page::IsBlankLine(int start, int length) {
    if (start >= 0 && length > 0 && m_Text && start + length <= m_Length) {
        for (int i = 0; i < length; ++i) {
            if (!is_blank(m_Text[start + i]) && !IsNewLine(m_Text[start + i]))
                return FALSE;
        }
    }
    return TRUE;
}

// ---------------------------------------------------------------------------
// Hooks + notifications
// ---------------------------------------------------------------------------

BOOL Page::IsValid(void) {
    return m_header && m_pIndex && m_Text && m_Length > 0;
}
BOOL Page::OnDrawPageEvent() { return TRUE; }
BOOL Page::OnUpDownEvent(int /*draw_type*/) { return TRUE; }
int  Page::GetTextBeginIndex(void) { return 0; }

void Page::NotifyRedraw(void) {
    if (m_listener)
        m_listener->on_book_event(reader::BookEvent::Redraw, (intptr_t)m_DrawType);
}
void Page::NotifySaveCache(void) {
    if (m_listener)
        m_listener->on_book_event(reader::BookEvent::SaveCache);
}

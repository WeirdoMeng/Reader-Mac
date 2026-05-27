// ReaderCore: cross-platform port of Reader/Page.h.
//
// Differences from upstream:
//  * No HDC/HFONT/HBITMAP/HWND on any signature. Text measurement is
//    delegated to ITextMetrics; drawing is the UI layer's job (Core Text
//    on macOS, GDI on Windows port if anyone needs one).
//  * DrawPage / DrawCover / DrawAlphaText / CreateAlphaTextBitmap removed;
//    Page now only computes layout. UI reads m_PageInfo and paints.
//  * BeginDraw/EndDraw and m_dcList[] font cache removed — font lifecycle
//    is owned by the ITextMetrics implementation.
//  * ReDraw / Save go through IBookListener.

#pragma once

#include "reader/platform.h"
#include "reader/types.h"
#include "reader/text_metrics.h"
#include "reader/book_listener.h"

#include <vector>

// ---------- public page layout types (same memory layout as upstream) ----------

typedef struct char_info_t {
    int idx;       // index into m_Text
    int dc_idx;    // 0 = body font, 1 = title font, 2+ = tag fonts
    int cx;        // advance in pixels (= measure_char(ch).advance_x)
    int cy;        // font height for this char (= measure_char(ch).line_height)
} char_info_t;

typedef struct line_info_t {
    int start;
    int length;
    int x;         // left indent inside content area
    int cy;        // tallest cy on this line
    int gap;       // gap after this line (LINE_GAP / PART_GAP / 0)
    char_info_t* chars;
    int char_cnt;
} line_info_t;

typedef struct lines_t {
    line_info_t* lines;
    int total;
    int used;
} lines_t;

typedef struct page_info_t {
    int    start;
    int    length;
    lines_t lines;
} page_info_t;

// Draw-type semantics carried over from upstream (used by CalcLayout).
#define DRAW_NULL       0
#define DRAW_PAGE_DOWN  1
#define DRAW_PAGE_UP    2
#define DRAW_LINE_DOWN  3
#define DRAW_LINE_UP    4

#define m_Index (*m_pIndex)

#define is_space(c)  ((c) == 0x20 || (c) == 0x09 || (c) == 0x0B || (c) == 0x0C)
#define is_hyphen(c) ((c) == 0x2D)
#define is_blank(c)  ((c) == 0x20 || (c) == 0x09 || (c) == 0x0B || (c) == 0x0C \
                      || (c) == 0x3000 || (c) == 0xA0)

class Page {
public:
    Page();
    virtual ~Page();

    // Wire dependencies. metrics + listener may be null in test scenarios
    // (layout call paths will short-circuit on missing metrics).
    void Init(int* p_index, header_t* header);
    void SetTextMetrics(reader::ITextMetrics* metrics) { m_metrics = metrics; }
    void SetListener(reader::IBookListener* listener)  { m_listener = listener; }

    // Navigation. `draw=true` notifies the listener to redraw; pass false
    // when the host is going to call CalcLayout itself.
    void PageUp(BOOL draw = TRUE);
    void PageDown(BOOL draw = TRUE);
    void LineUp(BOOL draw = TRUE);
    void LineDown(BOOL draw = TRUE);

    // Compute the page layout for a given content rect (in pixels).
    // Updates m_Index, m_PageLength, m_PageInfo. The UI layer paints
    // from m_PageInfo afterwards.
    void CalcLayout(int width, int height);

    // Query
    int    GetPageLength(void) const { return m_PageLength; }
    int    GetTextLength(void) const { return m_Length; }
    BOOL   IsFirstPage(void) const;
    BOOL   IsLastPage(void) const;
    BOOL   IsCoverPage(void) const;
    BOOL   IsBlankPage(void) const { return m_BlankPage; }
    double GetProgress(void) const;
    BOOL   GetCurPageText(TCHAR** text) const;
    const page_info_t* GetPageInfo(void) const { return &m_PageInfo; }

protected:
    // Hooks the Book subclass overrides.
    virtual BOOL IsValid(void);
    virtual BOOL OnDrawPageEvent();
    virtual BOOL OnUpDownEvent(int draw_type);
    virtual int  GetTextBeginIndex(void);
    virtual BOOL IsChapterIndex(int index) = 0;
    virtual BOOL IsChapter(int index) = 0;
    virtual BOOL GetChapterInfo(int type, int* start, int* length) = 0;
    // Cover image: Page core no longer paints it, but Book may still want
    // to mark "page 0 = cover". Subclasses return true if there is a cover
    // image associated with the book.
    virtual BOOL HasCover(void) const { return FALSE; }

    // ---- layout primitives ----
    int  SelectFont(int index, BOOL is_title);
    void SelectFontByDcIndex(int dc_idx);
    int  GetPrevParagraph(int start, int max_len, int* is_blank, int* crlf_len);
    int  GetNextParagraph(int start, int max_len, int* is_blank, int* crlf_len);
    int  ParagraphToLines(int start, int end, int width, int height, int line_idx);
    int  AddCharsToLine(int line_idx, char_info_t* chars,
                        int char_start, int char_len,
                        int line_start, int line_len,
                        int x, int cy, int gap);
    void RemoveLines(int line_idx, int count);
    void ClearLines(void);
    void ReleasePageInfo(void);

    void CalcPageDown(int width, int height);
    void CalcPageUp(int width, int height);
    int  GetMaxPageLength(int w, int h);
    int  GetIndentWidth(void);

    BOOL IsCover(int index);
    BOOL IsTitle(int index);
    BOOL IsNewLine(wchar_t c);
    BOOL IsBlankLine(int start, int length);

    // Notify listener that the layout changed; UI uses this to redraw.
    void NotifyRedraw(void);
    void NotifySaveCache(void);

protected:
    wchar_t*   m_Text;
    int        m_Length;
    int*       m_pIndex;
    int        m_PageLength;
    header_t*  m_header;

    reader::ITextMetrics* m_metrics;
    reader::IBookListener* m_listener;

private:
    page_info_t m_PageInfo;
    int         m_dcIndex;        // currently-selected font index (0 body, 1 title)
    int         m_LineCount;
    int         m_DrawType;
    BOOL        m_BlankPage;
    int         m_ChapterStart;   // for CHAPTER_PAGE
    int         m_ChapterLength;
};

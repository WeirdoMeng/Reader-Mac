// Smoke tests for the Page layout engine. Uses a deterministic mock
// ITextMetrics so the result is reproducible without any real font system.

#include "doctest/doctest.h"
#include "reader/defaults.h"
#include "reader/page.h"

#include <cstring>
#include <cwchar>
#include <vector>

// -------- mock metrics: monospace, ascii=10px wide, CJK=20px wide, height=20px --------
struct MockMetrics : public reader::ITextMetrics {
    void use_font(const reader::FontDesc&) override {}
    reader::CharMetrics measure_char(wchar_t ch) override {
        reader::CharMetrics m;
        m.advance_x = (ch < 0x80) ? 10 : 20;
        m.line_height = 20;
        m.ascent = 16;
        return m;
    }
    int indent_width() override { return 40; }  // two CJK ideographic spaces
};

// -------- minimal Book stub providing the pure virtual hooks Page demands --------
struct StubBook : public Page {
    StubBook() = default;
    BOOL IsChapterIndex(int) override { return FALSE; }
    BOOL IsChapter(int) override { return FALSE; }
    BOOL GetChapterInfo(int, int*, int*) override { return FALSE; }
};

static void set_text(Page* p, const wchar_t* literal,
                     wchar_t** out_text, int* out_len) {
    int n = (int)std::wcslen(literal);
    wchar_t* buf = (wchar_t*)std::malloc(sizeof(wchar_t) * (n + 1));
    std::memcpy(buf, literal, sizeof(wchar_t) * (n + 1));
    *out_text = buf;
    *out_len  = n;
    // Page's m_Text / m_Length are protected — reach in via friendship-by-subclass.
    struct Inj : public Page {
        using Page::m_Text;
        using Page::m_Length;
    };
    Inj* inj = reinterpret_cast<Inj*>(p);
    inj->m_Text   = buf;
    inj->m_Length = n;
}

TEST_CASE("Page lays out a short ASCII paragraph") {
    header_t header;
    reader::fill_default_header(&header);
    header.line_indent = 0;        // disable indent for predictable check
    header.blank_lines = 0;
    header.internal_border = {0, 0, 0, 0};

    int index = 0;
    StubBook book;
    MockMetrics metrics;
    book.Init(&index, &header);
    book.SetTextMetrics(&metrics);

    wchar_t* text = nullptr;
    int len = 0;
    set_text(&book, L"hello world", &text, &len);

    // 11 chars * 10px = 110px. width=200 fits whole paragraph on one line.
    book.CalcLayout(/*width=*/200, /*height=*/200);

    const page_info_t* pi = book.GetPageInfo();
    CHECK(pi->lines.used == 1);
    CHECK(pi->start == 0);
    CHECK(pi->length == 11);
    CHECK(pi->lines.lines[0].length == 11);
    CHECK(pi->lines.lines[0].cy == 20);
    CHECK(pi->lines.lines[0].char_cnt == 11);

    std::free(text);
}

TEST_CASE("Page wraps when paragraph exceeds line width") {
    header_t header;
    reader::fill_default_header(&header);
    header.line_indent = 0;
    header.blank_lines = 0;
    header.internal_border = {0, 0, 0, 0};
    header.char_gap = 0;
    header.word_wrap = 0;

    int index = 0;
    StubBook book;
    MockMetrics metrics;
    book.Init(&index, &header);
    book.SetTextMetrics(&metrics);

    wchar_t* text = nullptr;
    int len = 0;
    // 30 chars × 10 = 300 px → width=100 forces wrap every 10 chars
    set_text(&book, L"abcdefghijabcdefghijabcdefghij", &text, &len);

    book.CalcLayout(100, 200);
    const page_info_t* pi = book.GetPageInfo();
    CHECK(pi->lines.used >= 2);
    // each line should hold at most 10 ASCII chars
    for (int i = 0; i < pi->lines.used; ++i) {
        CHECK(pi->lines.lines[i].length <= 10);
    }

    std::free(text);
}

TEST_CASE("Page navigation: PageDown advances m_Index") {
    header_t header;
    reader::fill_default_header(&header);
    header.line_indent = 0;
    header.blank_lines = 0;
    header.internal_border = {0, 0, 0, 0};
    header.line_gap = 0;
    header.paragraph_gap = 0;

    int index = 0;
    StubBook book;
    MockMetrics metrics;
    book.Init(&index, &header);
    book.SetTextMetrics(&metrics);

    wchar_t* text = nullptr;
    int len = 0;
    // 200 chars, width=100 → 10 chars / line, height=60 → 3 lines / page = 30 chars / page
    std::wstring s;
    for (int i = 0; i < 200; ++i) s.push_back(L'x');
    set_text(&book, s.c_str(), &text, &len);

    book.CalcLayout(100, 60);
    const page_info_t* pi = book.GetPageInfo();
    int first_page_len = pi->length;
    CHECK(first_page_len > 0);
    CHECK(first_page_len <= 30);

    // PageDown then re-layout
    book.PageDown(/*draw=*/FALSE);
    book.CalcLayout(100, 60);
    int second_start = book.GetPageInfo()->start;
    CHECK(second_start == first_page_len);

    std::free(text);
}

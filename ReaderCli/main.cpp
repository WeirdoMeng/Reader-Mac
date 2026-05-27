// reader_cli — smoke test for ReaderCore. Loads a .txt file, paginates it
// with a mock fixed-width metrics, prints the chapter list and page
// boundaries. Validates that Book + Page + TextBook work end-to-end with
// no UI layer.

#include "reader/book_listener.h"
#include "reader/defaults.h"
#include "reader/page.h"
#include "reader/text_book.h"
#include "reader/text_metrics.h"
#include "reader/utils.h"

#include <chrono>
#include <cstdio>
#include <cstring>
#include <thread>

// --- mock text metrics: ASCII 10px, CJK 20px, line height 24px ---
struct MockMetrics : public reader::ITextMetrics {
    void use_font(const reader::FontDesc&) override {}
    reader::CharMetrics measure_char(wchar_t ch) override {
        reader::CharMetrics m;
        m.advance_x   = (ch < 0x80) ? 10 : 20;
        m.line_height = 24;
        m.ascent      = 20;
        return m;
    }
    int indent_width() override { return 40; }
};

// --- listener that just counts events for diagnostic output ---
struct SimpleListener : public reader::IBookListener {
    int open_finished_code = -1;
    int redraws            = 0;
    void on_book_event(reader::BookEvent e, intptr_t p1, intptr_t /*p2*/) override {
        switch (e) {
            case reader::BookEvent::OpenFinished:
                open_finished_code = (int)p1;
                break;
            case reader::BookEvent::Redraw:
                ++redraws;
                break;
            default:
                break;
        }
    }
};

static void utf8_to_wide(const char* s, wchar_t* out, size_t out_cap) {
    int len = 0;
    wchar_t* w = utf8_to_utf16(s, (int)std::strlen(s), &len);
    if (!w) { out[0] = 0; return; }
    int n = (len < (int)out_cap - 1) ? len : (int)out_cap - 1;
    std::memcpy(out, w, sizeof(wchar_t) * (size_t)n);
    out[n] = 0;
    free_buffer(w);
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::fprintf(stderr,
                     "Usage: %s <file.txt> [width=300] [height=400]\n", argv[0]);
        return 1;
    }
    int width  = (argc > 2) ? std::atoi(argv[2]) : 300;
    int height = (argc > 3) ? std::atoi(argv[3]) : 400;

    header_t header;
    reader::fill_default_header(&header);
    header.internal_border = {12, 12, 12, 12};
    header.blank_lines = 1;

    int index = 0;
    TextBook book;
    MockMetrics metrics;
    SimpleListener listener;
    book.Init(&index, &header);
    book.SetTextMetrics(&metrics);
    book.SetListener(&listener);

    wchar_t path[MAX_PATH] = {0};
    utf8_to_wide(argv[1], path, MAX_PATH);
    book.SetFileName(path);

    std::printf("Opening: %s (canvas %dx%d)\n", argv[1], width, height);
    book.OpenBook();

    // wait until ParserBook finishes
    auto t0 = std::chrono::steady_clock::now();
    while (listener.open_finished_code < 0) {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        auto dt = std::chrono::duration_cast<std::chrono::seconds>(
                      std::chrono::steady_clock::now() - t0).count();
        if (dt > 30) {
            std::fprintf(stderr, "Timeout waiting for parser\n");
            return 2;
        }
    }
    // join the worker thread before any further engine call
    while (book.IsLoading()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }

    if (listener.open_finished_code != 1) {
        std::fprintf(stderr, "Failed to parse book (code=%d)\n",
                     listener.open_finished_code);
        return 3;
    }

    std::printf("Text length: %d wchar_t's\n", book.GetTextLength());

    // chapters
    auto* chapters = book.GetChapters();
    std::printf("Chapters: %zu\n", chapters->size());
    int show = (int)chapters->size() < 10 ? (int)chapters->size() : 10;
    for (int i = 0; i < show; ++i) {
        const auto& c = (*chapters)[i];
        char title[256] = {0};
        int n = 0;
        char* t = utf16_to_utf8(c.title.c_str(), (int)c.title.size(), &n);
        if (t) {
            int copy = n < 255 ? n : 255;
            std::memcpy(title, t, (size_t)copy);
            title[copy] = 0;
            free_buffer(t);
        }
        std::printf("  [%4d] idx=%-7d %s\n", i, c.index, title);
    }
    if ((int)chapters->size() > show) {
        std::printf("  ... (%zu more)\n", chapters->size() - show);
    }

    // paginate first 5 pages
    std::printf("\nLayout: first 5 pages\n");
    for (int p = 0; p < 5 && !book.IsLastPage(); ++p) {
        book.CalcLayout(width, height);
        const page_info_t* pi = book.GetPageInfo();
        std::printf("  page %d: start=%d length=%d lines=%d progress=%.1f%%\n",
                    p + 1, pi->start, pi->length, pi->lines.used,
                    book.GetProgress());
        book.PageDown(/*draw=*/FALSE);
    }
    FreeConvertBuffer();
    return 0;
}

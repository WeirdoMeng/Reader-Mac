// ReaderCore: abstract text measurement interface.
//
// Page.cpp originally called GetTextExtentPoint32W(HDC, ...) to measure each
// glyph during layout. To run that engine off Windows, we factor the
// measurement out into an interface; the macOS UI implements it with
// Core Text, the Windows port keeps using GDI.

#pragma once

#include "reader/platform.h"

namespace reader {

// One physical font (lfHeight/lfWeight/lfFaceName/italic/etc.) the engine is
// currently using. The Page engine asks the metrics object to "switch font"
// before measuring runs of characters drawn with that font.
struct FontDesc {
    const LOGFONT* logfont;   // points into header_t; not owned
    bool           is_title;  // some books use a separate title font
};

// Per-glyph measurement result.
struct CharMetrics {
    int advance_x;            // advance in device pixels for this glyph
    int line_height;          // line box height for this font
    int ascent;               // baseline ascent (positive)
};

// Implemented per UI backend (Core Text on macOS, GDI on Windows).
// Lifetime: created by the UI layer once, kept alive while a book is open.
class ITextMetrics {
public:
    virtual ~ITextMetrics() = default;

    // Switch the active font. Must be called before any measure_*.
    virtual void use_font(const FontDesc& desc) = 0;

    // Measure a single Unicode code point under the current font.
    // For surrogate-pair handling, the engine sends the high+low together as
    // a 32-bit value where bit 16 == 1 indicates surrogate pair.
    virtual CharMetrics measure_char(wchar_t ch) = 0;

    // Optional optimization: measure a run in one call. Default impl loops.
    virtual void measure_run(const wchar_t* text,
                             int length,
                             CharMetrics* out_per_char) {
        for (int i = 0; i < length; ++i) {
            out_per_char[i] = measure_char(text[i]);
        }
    }

    // Indent width = width of two ideographic spaces (U+3000) in the current
    // font. Used by Page::GetIndentWidth for first-line indent.
    virtual int indent_width() = 0;
};

}  // namespace reader

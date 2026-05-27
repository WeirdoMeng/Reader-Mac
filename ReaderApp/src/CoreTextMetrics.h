// Core Text-backed implementation of reader::ITextMetrics.

#pragma once

#include "reader/text_metrics.h"

#ifdef __OBJC__
#import <CoreText/CoreText.h>
#endif

namespace reader_mac {

class CoreTextMetrics : public reader::ITextMetrics {
public:
    CoreTextMetrics();
    ~CoreTextMetrics() override;

    void use_font(const reader::FontDesc& desc) override;
    reader::CharMetrics measure_char(wchar_t ch) override;
    int  indent_width() override;

private:
    void clear_font();

    // Held as void* to keep this header includable from plain C++ TUs;
    // the .mm file casts back to CTFontRef.
    void*  m_ctfont = nullptr;
    int    m_line_height = 24;
    int    m_ascent = 20;
    int    m_indent = 24;  // recomputed on font change
};

}  // namespace reader_mac

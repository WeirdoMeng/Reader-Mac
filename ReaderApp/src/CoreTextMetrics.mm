// Core Text implementation of ITextMetrics.

#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>

#include "CoreTextMetrics.h"
#include "reader/types.h"

#include <cstring>

namespace reader_mac {

CoreTextMetrics::CoreTextMetrics() {
    // Pick a sensible default font so measurements work before use_font().
    reader::FontDesc fd{nullptr, false};
    use_font(fd);
}

CoreTextMetrics::~CoreTextMetrics() {
    clear_font();
}

void CoreTextMetrics::clear_font() {
    if (m_ctfont) {
        CFRelease((CTFontRef)m_ctfont);
        m_ctfont = nullptr;
    }
}

static NSString* wchar_to_nsstring(const wchar_t* w, size_t cap) {
    if (!w || !w[0]) return nil;
    size_t n = 0;
    while (n < cap && w[n]) ++n;
    NSData* d = [NSData dataWithBytes:w length:n * sizeof(wchar_t)];
    return [[NSString alloc] initWithData:d
                                 encoding:NSUTF32LittleEndianStringEncoding];
}

void CoreTextMetrics::use_font(const reader::FontDesc& desc) {
    clear_font();
    // Map LOGFONT to NSFont attributes (face name + size).
    NSString* face = nil;
    CGFloat size = 14.0;
    if (desc.logfont) {
        face = wchar_to_nsstring(desc.logfont->lfFaceName, 32);
        // LOGFONT lfHeight: negative = font size in points;
        // positive = cell height in pixels.
        if (desc.logfont->lfHeight < 0) size = (CGFloat)(-desc.logfont->lfHeight);
        else if (desc.logfont->lfHeight > 0) size = (CGFloat)desc.logfont->lfHeight;
    }
    if (size < 6.0)  size = 6.0;
    if (size > 96.0) size = 96.0;

    CTFontRef font = nullptr;
    if (face.length > 0) {
        font = CTFontCreateWithName((__bridge CFStringRef)face, size, nullptr);
    }
    if (!font) {
        // fallback: use system font that supports CJK well
        NSFont* sys = [NSFont fontWithName:@"PingFang SC" size:size];
        if (!sys) sys = [NSFont systemFontOfSize:size];
        font = (CTFontRef)CFBridgingRetain(sys);
    }
    m_ctfont = (void*)font;
    m_line_height = (int)ceil(CTFontGetAscent(font) +
                              CTFontGetDescent(font) +
                              CTFontGetLeading(font));
    m_ascent      = (int)ceil(CTFontGetAscent(font));

    // indent width = width of two U+3000 ideographic spaces.
    unichar chars[2] = {0x3000, 0x3000};
    CGGlyph glyphs[2] = {0};
    CGSize  adv[2]    = {{0, 0}, {0, 0}};
    if (CTFontGetGlyphsForCharacters(font, chars, glyphs, 2)) {
        CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, glyphs, adv, 2);
        m_indent = (int)ceil(adv[0].width + adv[1].width);
    } else {
        m_indent = (int)ceil(size * 2);
    }
}

reader::CharMetrics CoreTextMetrics::measure_char(wchar_t ch) {
    reader::CharMetrics m{0, m_line_height, m_ascent};
    if (!m_ctfont) return m;
    CTFontRef font = (CTFontRef)m_ctfont;

    // Encode the code point as UTF-16 (Core Text speaks UTF-16).
    UniChar units[2];
    CFIndex count = 0;
    uint32_t cp = (uint32_t)ch;
    if (cp <= 0xFFFF) {
        units[0] = (UniChar)cp;
        count = 1;
    } else {
        uint32_t v = cp - 0x10000;
        units[0] = (UniChar)(0xD800 | (v >> 10));
        units[1] = (UniChar)(0xDC00 | (v & 0x3FF));
        count = 2;
    }

    CGGlyph glyphs[2] = {0, 0};
    if (!CTFontGetGlyphsForCharacters(font, units, glyphs, count)) {
        m.advance_x = (int)ceil(CTFontGetSize(font) * 0.5);
        return m;
    }
    CGSize adv[2] = {{0, 0}, {0, 0}};
    CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, glyphs, adv, count);
    double total = adv[0].width + (count == 2 ? adv[1].width : 0.0);
    m.advance_x = (int)ceil(total);
    return m;
}

int CoreTextMetrics::indent_width() { return m_indent; }

}  // namespace reader_mac

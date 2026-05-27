// ReaderCanvasView — owns Book engine, listens to book events, paints
// the current page with Core Text.

#import "ReaderCanvasView.h"
#import <CoreText/CoreText.h>

#include "CoreTextMetrics.h"
#include "reader/book.h"
#include "reader/book_listener.h"
#include "reader/defaults.h"
#include "reader/epub_book.h"
#include "reader/mobi_book.h"
#include "reader/page.h"
#include "reader/text_book.h"
#include "reader/utils.h"

#include <cstring>
#include <memory>

// ---------------------------------------------------------------------------
// IBookListener that forwards events onto the main thread / NSView redraw.
// ---------------------------------------------------------------------------
class ViewListener : public reader::IBookListener {
public:
    ReaderCanvasView* __weak view = nil;
    void on_book_event(reader::BookEvent e, intptr_t /*p1*/, intptr_t /*p2*/) override {
        ReaderCanvasView* v = view;
        dispatch_async(dispatch_get_main_queue(), ^{
            switch (e) {
                case reader::BookEvent::OpenFinished:
                case reader::BookEvent::Redraw:
                case reader::BookEvent::ChaptersUpdated:
                    [v relayoutAndRedraw];
                    break;
                default: break;
            }
        });
    }
};

@interface ReaderCanvasView ()
@property (copy)   NSString* currentFilePath;
@property (assign) int       pendingRestoreIndex;
@end

@implementation ReaderCanvasView {
    std::unique_ptr<Book>                       _book;
    std::unique_ptr<reader_mac::CoreTextMetrics> _metrics;
    std::unique_ptr<ViewListener>                _listener;
    header_t                                     _header;
    int                                          _index;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _index = 0;
        reader::fill_default_header(&_header);
        _header.internal_border = {20, 20, 20, 20};
        _metrics  = std::make_unique<reader_mac::CoreTextMetrics>();
        _listener = std::make_unique<ViewListener>();
        _listener->view = self;
        self.wantsLayer = YES;
        self.layer.backgroundColor =
            [NSColor.windowBackgroundColor CGColor];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }       // top-left origin matches the engine
- (BOOL)acceptsFirstResponder { return YES; }

- (void)closeBook {
    _book.reset();
    self.currentFilePath = nil;
    [self setNeedsDisplay:YES];
}

- (NSString*)currentPath { return self.currentFilePath; }
- (int)currentIndex      { return _index; }

- (BOOL)openFileAtPath:(NSString*)path {
    return [self openFileAtPath:path restoreIndex:0];
}

- (BOOL)openFileAtPath:(NSString*)path restoreIndex:(int)idx {
    [self closeBook];
    self.currentFilePath = path;
    self.pendingRestoreIndex = idx;
    NSString* lower = path.lowercaseString;
    if ([lower hasSuffix:@".epub"]) {
        _book = std::make_unique<EpubBook>();
    } else if ([lower hasSuffix:@".mobi"] || [lower hasSuffix:@".azw"]
               || [lower hasSuffix:@".azw3"]) {
        _book = std::make_unique<MobiBook>();
    } else {
        _book = std::make_unique<TextBook>();
    }

    _index = 0;
    _book->Init(&_index, &_header);
    _book->SetTextMetrics(_metrics.get());
    _book->SetListener(_listener.get());

    // wchar_t path (4 bytes on macOS)
    NSData* d = [path dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
    int wlen = (int)(d.length / sizeof(wchar_t));
    wchar_t wpath[1024] = {0};
    int copy = wlen < 1023 ? wlen : 1023;
    std::memcpy(wpath, d.bytes, (size_t)copy * sizeof(wchar_t));
    wpath[copy] = 0;
    _book->SetFileName(wpath);

    return _book->OpenBook();
}

- (void)relayoutAndRedraw {
    if (!_book) { [self setNeedsDisplay:YES]; return; }
    // Apply pending restore-index once the parser has populated m_Text.
    if (self.pendingRestoreIndex > 0 && _book->GetTextLength() > 0) {
        int clamped = self.pendingRestoreIndex;
        int total = _book->GetTextLength();
        if (clamped < 0) clamped = 0;
        if (clamped > total - 1) clamped = total - 1;
        _index = clamped;
        self.pendingRestoreIndex = 0;
    }
    NSSize sz = self.bounds.size;
    _book->CalcLayout((int)sz.width, (int)sz.height);
    [self saveProgressToUserDefaults];
    [self setNeedsDisplay:YES];
}

- (void)saveProgressToUserDefaults {
    NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
    if (self.currentFilePath) {
        [d setObject:self.currentFilePath forKey:@"lastFile"];
        [d setInteger:_index             forKey:@"lastIndex"];
    } else {
        [d removeObjectForKey:@"lastFile"];
        [d removeObjectForKey:@"lastIndex"];
    }
}

- (void)viewDidEndLiveResize {
    [super viewDidEndLiveResize];
    [self relayoutAndRedraw];
}

- (double)progress {
    return _book ? _book->GetProgress() : 0.0;
}

// ---------- keyboard navigation ----------
- (void)keyDown:(NSEvent*)event {
    if (!_book) { [super keyDown:event]; return; }
    NSString* chars = event.charactersIgnoringModifiers;
    unichar key = chars.length ? [chars characterAtIndex:0] : 0;
    BOOL ctrl  = (event.modifierFlags & NSEventModifierFlagControl) != 0;
    switch (key) {
        case NSLeftArrowFunctionKey:
            if (ctrl) _book->JumpPrevChapter(); else _book->PageUp();
            break;
        case NSRightArrowFunctionKey:
            if (ctrl) _book->JumpNextChapter(); else _book->PageDown();
            break;
        case NSUpArrowFunctionKey:   _book->LineUp(); break;
        case NSDownArrowFunctionKey: _book->LineDown(); break;
        default: [super keyDown:event]; return;
    }
}

// ---------- mouse: left = next, right = prev ----------
- (void)mouseDown:(NSEvent*)event {
    if (_book) _book->PageDown();
}
- (void)rightMouseDown:(NSEvent*)event {
    if (_book) _book->PageUp();
}

// ---------- scroll wheel: line up / down ----------
- (void)scrollWheel:(NSEvent*)event {
    if (!_book) return;
    if (event.deltaY > 0.5)      _book->LineUp();
    else if (event.deltaY < -0.5) _book->LineDown();
}

// ---------------------------------------------------------------------------
// Paint
// ---------------------------------------------------------------------------
- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = [NSGraphicsContext currentContext].CGContext;
    if (!ctx) return;

    // background
    CGContextSetFillColorWithColor(ctx,
        [NSColor.windowBackgroundColor CGColor]);
    CGContextFillRect(ctx, self.bounds);

    if (!_book) {
        NSString* hint = @"Cmd+O to open .txt / .epub / .mobi";
        NSDictionary* attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:16],
            NSForegroundColorAttributeName:
                [NSColor secondaryLabelColor]
        };
        NSSize size = [hint sizeWithAttributes:attrs];
        NSPoint p = NSMakePoint((self.bounds.size.width - size.width) / 2,
                                (self.bounds.size.height - size.height) / 2);
        [hint drawAtPoint:p withAttributes:attrs];
        return;
    }

    const page_info_t* pi = _book->GetPageInfo();
    if (!pi || pi->lines.used == 0) return;

    wchar_t* text = _book->GetText();
    if (!text) return;

    // text color
    NSColor* fg = [NSColor labelColor];
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [[fg colorUsingColorSpace:NSColorSpace.sRGBColorSpace]
        getRed:&r green:&g blue:&b alpha:&a];

    const int LEFT_MIN = _header.internal_border.left;
    const int TOP_MIN  = _header.internal_border.top;

    NSFont* font = [NSFont fontWithName:@"PingFang SC" size:16];
    if (!font) font = [NSFont systemFontOfSize:16];

    // Draw per-line: build NSAttributedString for the whole line and use
    // CTLineCreateWithAttributedString for proper kerning + complex script.
    int y = TOP_MIN;
    for (int i = 0; i < pi->lines.used; ++i) {
        const line_info_t& line = pi->lines.lines[i];
        if (line.length <= 0 || line.start < 0) {
            y += line.cy + line.gap;
            continue;
        }
        // Skip CRLF chars at the line end when rendering — they make the
        // CTLine emit a visible glyph on macOS.
        int eff_len = line.length;
        while (eff_len > 0) {
            wchar_t c = text[line.start + eff_len - 1];
            if (c == 0x0A || c == 0x0D) --eff_len; else break;
        }
        if (eff_len <= 0) {
            y += line.cy + line.gap;
            continue;
        }

        NSData* d = [NSData dataWithBytes:(text + line.start)
                                   length:(NSUInteger)eff_len * sizeof(wchar_t)];
        NSString* s = [[NSString alloc] initWithData:d
                                            encoding:NSUTF32LittleEndianStringEncoding];
        if (!s) { y += line.cy + line.gap; continue; }

        NSDictionary* attrs = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: fg
        };
        NSAttributedString* astr = [[NSAttributedString alloc] initWithString:s
                                                                  attributes:attrs];
        CTLineRef ctl = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)astr);
        if (!ctl) { y += line.cy + line.gap; continue; }

        // baseline = y + ascent
        CGContextSaveGState(ctx);
        CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
        CGContextSetTextPosition(ctx,
                                 (CGFloat)(LEFT_MIN + line.x),
                                 (CGFloat)(y + (int)CTFontGetAscent((CTFontRef)font)));
        // Our view is flipped; flip y back inside the text draw so glyphs
        // are upright.
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGContextSetTextPosition(ctx,
                                 (CGFloat)(LEFT_MIN + line.x),
                                 (CGFloat)(-(y + (int)CTFontGetAscent((CTFontRef)font))));
        CTLineDraw(ctl, ctx);
        CGContextRestoreGState(ctx);
        CFRelease(ctl);

        y += line.cy + line.gap;
    }
}

@end

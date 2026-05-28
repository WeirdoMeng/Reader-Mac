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
#include <vector>

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
@property (strong) NSColor*  textColorCache;
@property (strong) NSColor*  bgColorCache;
// 自动翻页
@property (strong) NSTimer*  autoPagingTimer;
@property (assign) double    autoPagingInterval;
// 全文搜索
@property (copy)   NSString*           lastSearchKeyword;
@property (strong) NSMutableArray<NSNumber*>* searchHits;
@property (assign) NSInteger           searchHitIndex;
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
        self.textColorCache = [NSColor labelColor];
        self.bgColorCache   = [NSColor windowBackgroundColor];
        _autoPagingInterval = 5.0;
        [self loadDisplayProfileFromUserDefaults];
        self.wantsLayer = YES;
        self.layer.backgroundColor = [self.bgColorCache CGColor];
        // 拖拽打开文件
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

// ---------- 拖拽接收 ----------

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard* pb = sender.draggingPasteboard;
    NSArray* urls = [pb readObjectsForClasses:@[NSURL.class] options:nil];
    for (NSURL* u in urls) {
        NSString* ext = u.pathExtension.lowercaseString;
        if ([@[@"txt", @"epub", @"mobi", @"azw", @"azw3"] containsObject:ext]) {
            return NSDragOperationCopy;
        }
    }
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard* pb = sender.draggingPasteboard;
    NSArray* urls = [pb readObjectsForClasses:@[NSURL.class] options:nil];
    for (NSURL* u in urls) {
        NSString* ext = u.pathExtension.lowercaseString;
        if ([@[@"txt", @"epub", @"mobi", @"azw", @"azw3"] containsObject:ext]) {
            [self openFileAtPath:u.path];
            self.window.title = u.lastPathComponent;
            return YES;
        }
    }
    return NO;
}

- (BOOL)hasBook { return _book != nullptr; }
- (void)pageUp        { if (_book) _book->PageUp(); }
- (void)pageDown      { if (_book) _book->PageDown(); }
- (void)lineUp        { if (_book) _book->LineUp(); }
- (void)lineDown      { if (_book) _book->LineDown(); }
- (void)jumpPrevChapter { if (_book) _book->JumpPrevChapter(); }
- (void)jumpNextChapter { if (_book) _book->JumpNextChapter(); }

- (void)increaseFontSize { [self setFontSize:[self fontSize] + 2]; }
- (void)decreaseFontSize { [self setFontSize:[self fontSize] - 2]; }

- (void)jumpToPercent:(double)pct {
    if (!_book || _book->GetTextLength() <= 0) return;
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    int total = _book->GetTextLength();
    _index = (int)(total * pct / 100.0);
    if (_index >= total) _index = total - 1;
    [self relayoutAndRedraw];
}

// ---------- 自动翻页 ----------

- (BOOL)isAutoPaging { return self.autoPagingTimer != nil; }

- (void)setAutoPagingInterval:(double)seconds {
    _autoPagingInterval = seconds;   // 直接赋值 ivar，避免递归调用 setter
    if ([self isAutoPaging]) {        // restart with new interval
        [self toggleAutoPaging];
        [self toggleAutoPaging];
    }
}

- (void)toggleAutoPaging {
    if (self.autoPagingTimer) {
        [self.autoPagingTimer invalidate];
        self.autoPagingTimer = nil;
        return;
    }
    if (!_book) return;
    double interval = self.autoPagingInterval > 0 ? self.autoPagingInterval : 5.0;
    __weak typeof(self) ws = self;
    self.autoPagingTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                            repeats:YES
                                                              block:^(NSTimer* t) {
        __strong typeof(ws) ss = ws;
        if (!ss || !ss.hasBook) { [t invalidate]; return; }
        if ([ss isAtLastPage]) {
            [t invalidate];
            ss.autoPagingTimer = nil;
            return;
        }
        [ss pageDown];
    }];
}

- (BOOL)isAtLastPage { return _book && _book->IsLastPage(); }

// ---------- 全文搜索 ----------

- (NSUInteger)searchText:(NSString*)keyword {
    self.lastSearchKeyword = keyword;
    self.searchHits = [NSMutableArray array];
    self.searchHitIndex = -1;
    if (!_book || keyword.length == 0) return 0;

    int textLen = _book->GetTextLength();
    if (textLen <= 0) return 0;

    // m_Text 是 protected，靠 GetText 拿；ReaderCore 已暴露
    wchar_t* text = _book->GetText();
    if (!text) return 0;

    // 转关键词为 wchar_t（macOS wchar_t = 4 字节 / UTF-32）
    NSData* d = [keyword dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
    int klen = (int)(d.length / sizeof(wchar_t));
    if (klen <= 0) return 0;
    const wchar_t* kbuf = (const wchar_t*)d.bytes;

    // 顺序扫描所有出现位置（小说一般不长，性能足够）
    for (int i = 0; i + klen <= textLen; ++i) {
        BOOL hit = YES;
        for (int j = 0; j < klen; ++j) {
            if (text[i + j] != kbuf[j]) { hit = NO; break; }
        }
        if (hit) {
            [self.searchHits addObject:@(i)];
            i += klen - 1;
        }
    }
    return self.searchHits.count;
}

- (void)jumpToNextMatch {
    if (self.searchHits.count == 0) return;
    self.searchHitIndex = (self.searchHitIndex + 1) % (NSInteger)self.searchHits.count;
    int idx = [self.searchHits[self.searchHitIndex] intValue];
    _index = idx;
    [self relayoutAndRedraw];
}

- (void)jumpToPrevMatch {
    if (self.searchHits.count == 0) return;
    self.searchHitIndex = (self.searchHitIndex - 1 + (NSInteger)self.searchHits.count)
                        % (NSInteger)self.searchHits.count;
    int idx = [self.searchHits[self.searchHitIndex] intValue];
    _index = idx;
    [self relayoutAndRedraw];
}

- (NSString*)currentSearchInfo {
    if (self.searchHits.count == 0)
        return self.lastSearchKeyword.length > 0 ? @"无匹配" : @"";
    return [NSString stringWithFormat:@"%ld/%lu",
            (long)(self.searchHitIndex < 0 ? 0 : self.searchHitIndex + 1),
            (unsigned long)self.searchHits.count];
}

// ---------- 当前章节标题 ----------

- (NSString*)currentChapterTitle {
    if (!_book) return @"";
    int ci = _book->GetCurChapterIndex();
    auto* chapters = _book->GetChapters();
    if (!chapters || ci < 0 || ci >= (int)chapters->size()) return @"";
    const std::wstring& t = (*chapters)[ci].title;
    NSData* d = [NSData dataWithBytes:t.data() length:t.size() * sizeof(wchar_t)];
    NSString* s = [[NSString alloc] initWithData:d
                                         encoding:NSUTF32LittleEndianStringEncoding];
    return s ?: @"";
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
    // Restore reading position from history for this file (per-book memory).
    int restore = [[self class] recentIndexFor:path];
    return [self openFileAtPath:path restoreIndex:restore];
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

// ---------- chapters / bookmarks ----------

- (NSArray<NSDictionary*>*)chapters {
    if (!_book) return @[];
    NSMutableArray* out = [NSMutableArray array];
    chapters_t* chs = _book->GetChapters();
    for (auto& c : *chs) {
        NSData* d = [NSData dataWithBytes:c.title.data()
                                   length:c.title.size() * sizeof(wchar_t)];
        NSString* title = [[NSString alloc] initWithData:d
                                                encoding:NSUTF32LittleEndianStringEncoding] ?: @"(untitled)";
        [out addObject:@{@"title": title, @"index": @(c.index)}];
    }
    return out;
}

- (void)jumpToTextIndex:(int)idx {
    if (!_book) return;
    int total = _book->GetTextLength();
    if (idx < 0) idx = 0;
    if (idx > total - 1) idx = total > 0 ? total - 1 : 0;
    _index = idx;
    [self relayoutAndRedraw];
}

- (void)jumpToChapterAtListIndex:(int)i {
    if (!_book) return;
    _book->JumpChapter(i);
    // JumpChapter already fires Redraw event; ensure layout after jump.
    [self relayoutAndRedraw];
}

static NSString* bookmarkKeyFor(NSString* file) {
    return [NSString stringWithFormat:@"bookmarks::%@", file];
}

- (NSArray<NSNumber*>*)bookmarks {
    if (!self.currentFilePath) return @[];
    NSArray* arr = [NSUserDefaults.standardUserDefaults
                      arrayForKey:bookmarkKeyFor(self.currentFilePath)];
    return arr ?: @[];
}

- (void)addBookmarkAtCurrentLocation {
    if (!self.currentFilePath || !_book) return;
    NSMutableArray* arr = [[self bookmarks] mutableCopy] ?: [NSMutableArray array];
    NSNumber* mark = @(_index);
    if (![arr containsObject:mark]) [arr addObject:mark];
    [NSUserDefaults.standardUserDefaults
        setObject:arr forKey:bookmarkKeyFor(self.currentFilePath)];
}

- (void)removeBookmarkAtIndex:(int)i {
    if (!self.currentFilePath) return;
    NSMutableArray* arr = [[self bookmarks] mutableCopy];
    if (i < 0 || i >= (int)arr.count) return;
    [arr removeObjectAtIndex:i];
    [NSUserDefaults.standardUserDefaults
        setObject:arr forKey:bookmarkKeyFor(self.currentFilePath)];
}

// ---------- display setting accessors ----------

- (int)fontSize {
    return _header.font.lfHeight < 0 ? -_header.font.lfHeight
                                     : (_header.font.lfHeight > 0
                                            ? _header.font.lfHeight
                                            : 16);
}
- (void)setFontSize:(int)pt {
    if (pt < 8)  pt = 8;
    if (pt > 64) pt = 64;
    _header.font.lfHeight       = -pt;
    _header.font_title.lfHeight = -pt;
    if (_book) _book->InvalidateFontCache();  // force re-measure with new size
    [self relayoutAndRedraw];
    [self saveDisplayProfileToUserDefaults];
}

- (int)charGap { return _header.char_gap; }
- (void)setCharGap:(int)px {
    if (px < 0)  px = 0;
    if (px > 10) px = 10;
    _header.char_gap = px;
    if (_book) _book->InvalidateFontCache();
    [self relayoutAndRedraw];
    [self saveDisplayProfileToUserDefaults];
}

- (int)lineGap { return _header.line_gap; }
- (void)setLineGap:(int)px {
    if (px < 0) px = 0;
    if (px > 40) px = 40;
    _header.line_gap = px;
    [self relayoutAndRedraw];
    [self saveDisplayProfileToUserDefaults];
}

- (int)paragraphGap { return _header.paragraph_gap; }
- (void)setParagraphGap:(int)px {
    if (px < 0) px = 0;
    if (px > 80) px = 80;
    _header.paragraph_gap = px;
    [self relayoutAndRedraw];
    [self saveDisplayProfileToUserDefaults];
}

- (BOOL)firstLineIndent { return _header.line_indent != 0; }
- (void)setFirstLineIndent:(BOOL)on {
    _header.line_indent = on ? 1 : 0;
    [self relayoutAndRedraw];
    [self saveDisplayProfileToUserDefaults];
}

- (NSColor*)textColor { return self.textColorCache; }
- (void)setTextColor:(NSColor*)c {
    self.textColorCache = c ?: [NSColor labelColor];
    [self setNeedsDisplay:YES];
    [self saveDisplayProfileToUserDefaults];
}

- (NSColor*)backgroundColor { return self.bgColorCache; }
- (void)setBackgroundColor:(NSColor*)c {
    self.bgColorCache = c ?: [NSColor windowBackgroundColor];
    self.layer.backgroundColor = [self.bgColorCache CGColor];
    [self setNeedsDisplay:YES];
    [self saveDisplayProfileToUserDefaults];
}

// ---------- profile persistence ----------

static NSData* archiveColor(NSColor* c) {
    if (!c) return nil;
    return [NSKeyedArchiver archivedDataWithRootObject:c
                                 requiringSecureCoding:NO error:nil];
}
static NSColor* unarchiveColor(NSData* d) {
    if (!d) return nil;
    return [NSKeyedUnarchiver unarchivedObjectOfClass:NSColor.class
                                             fromData:d error:nil];
}

- (void)loadDisplayProfileFromUserDefaults {
    NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
    if ([d objectForKey:@"fontSize"])    _header.font.lfHeight = -(int)[d integerForKey:@"fontSize"];
    if ([d objectForKey:@"fontSize"])    _header.font_title.lfHeight = _header.font.lfHeight;
    if ([d objectForKey:@"charGap"])     _header.char_gap = (int)[d integerForKey:@"charGap"];
    if ([d objectForKey:@"lineGap"])     _header.line_gap = (int)[d integerForKey:@"lineGap"];
    if ([d objectForKey:@"paragraphGap"])_header.paragraph_gap = (int)[d integerForKey:@"paragraphGap"];
    if ([d objectForKey:@"lineIndent"])  _header.line_indent = (int)[d integerForKey:@"lineIndent"];
    NSColor* tc = unarchiveColor([d objectForKey:@"textColor"]);
    NSColor* bc = unarchiveColor([d objectForKey:@"bgColor"]);
    if (tc) self.textColorCache = tc;
    if (bc) self.bgColorCache   = bc;
}

- (void)saveDisplayProfileToUserDefaults {
    NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
    [d setInteger:[self fontSize]      forKey:@"fontSize"];
    [d setInteger:_header.char_gap     forKey:@"charGap"];
    [d setInteger:_header.line_gap     forKey:@"lineGap"];
    [d setInteger:_header.paragraph_gap forKey:@"paragraphGap"];
    [d setInteger:_header.line_indent  forKey:@"lineIndent"];
    [d setObject:archiveColor(self.textColorCache) forKey:@"textColor"];
    [d setObject:archiveColor(self.bgColorCache)   forKey:@"bgColor"];
}

- (void)saveProgressToUserDefaults {
    NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
    if (self.currentFilePath) {
        [d setObject:self.currentFilePath forKey:@"lastFile"];
        [d setInteger:_index             forKey:@"lastIndex"];
        [[self class] updateRecentBook:self.currentFilePath index:_index];
    } else {
        [d removeObjectForKey:@"lastFile"];
        [d removeObjectForKey:@"lastIndex"];
    }
}

// ---------- recent books history ----------

+ (NSArray<NSDictionary*>*)recentBooks {
    NSArray* a = [NSUserDefaults.standardUserDefaults arrayForKey:@"recentBooks"];
    return a ?: @[];
}

+ (void)updateRecentBook:(NSString*)path index:(int)idx {
    if (!path) return;
    NSMutableArray* arr = [[[self class] recentBooks] mutableCopy] ?: [NSMutableArray array];
    // remove duplicate
    NSMutableArray* dup = [NSMutableArray array];
    for (NSDictionary* e in arr) {
        if ([e[@"path"] isEqualToString:path]) [dup addObject:e];
    }
    [arr removeObjectsInArray:dup];
    // insert at front
    [arr insertObject:@{ @"path": path,
                         @"index": @(idx),
                         @"openedAt": @([NSDate.now timeIntervalSince1970]) }
              atIndex:0];
    // cap at 20
    if (arr.count > 20) [arr removeObjectsInRange:NSMakeRange(20, arr.count - 20)];
    [NSUserDefaults.standardUserDefaults setObject:arr forKey:@"recentBooks"];
}

+ (int)recentIndexFor:(NSString*)path {
    for (NSDictionary* e in [[self class] recentBooks]) {
        if ([e[@"path"] isEqualToString:path]) return [e[@"index"] intValue];
    }
    return 0;
}

+ (void)clearRecentBooks {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"recentBooks"];
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
    NSString* chars = event.charactersIgnoringModifiers;
    unichar key = chars.length ? [chars characterAtIndex:0] : 0;
    if (!_book) { [super keyDown:event]; return; }
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
        case ' ':  // 空格：自动翻页切换
            [self toggleAutoPaging];
            break;
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

// ---------- scroll wheel: line up / down (Ctrl = window alpha) ----------
- (void)scrollWheel:(NSEvent*)event {
    BOOL ctrl  = (event.modifierFlags & NSEventModifierFlagControl) != 0;
    BOOL shift = (event.modifierFlags & NSEventModifierFlagShift)   != 0;
    if (ctrl) {
        NSWindow* w = self.window;
        CGFloat a = w.alphaValue;
        if (shift) {
            // Ctrl + Shift: snap to extreme
            a = (event.deltaY > 0) ? 0.05 : 1.0;
        } else {
            a += (event.deltaY > 0) ? -0.05 : 0.05;
            if (a < 0.1) a = 0.1;
            if (a > 1.0) a = 1.0;
        }
        w.alphaValue = a;
        [NSUserDefaults.standardUserDefaults setDouble:a forKey:@"windowAlpha"];
        return;
    }
    if (!_book) return;
    if (event.deltaY > 0.5)        _book->LineUp();
    else if (event.deltaY < -0.5)  _book->LineDown();
}

// ---------------------------------------------------------------------------
// Paint
// ---------------------------------------------------------------------------
- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = [NSGraphicsContext currentContext].CGContext;
    if (!ctx) return;

    // 把窗口背景也同步，避免 borderless 时左右色差
    if (self.window && !self.window.opaque == NO) {
        // skip if window is intentionally clear (borderless transparent mode)
    } else if (self.window) {
        self.window.backgroundColor = self.bgColorCache;
    }

    // background
    CGContextSetFillColorWithColor(ctx, [self.bgColorCache CGColor]);
    CGContextFillRect(ctx, self.bounds);

    if (!_book) {
        NSString* hint = @"按 Cmd+O 打开 .txt / .epub / .mobi";
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
    NSColor* fg = self.textColorCache ?: [NSColor labelColor];
    CGFloat fr=0, fgC=0, fb=0, fa=1;
    [[fg colorUsingColorSpace:NSColorSpace.sRGBColorSpace]
        getRed:&fr green:&fgC blue:&fb alpha:&fa];
    CGContextSetRGBFillColor(ctx, fr, fgC, fb, fa);

    const int LEFT_MIN = _header.internal_border.left;
    const int TOP_MIN  = _header.internal_border.top;
    const int CHAR_GAP = _header.char_gap;

    CGFloat fontPt = _header.font.lfHeight < 0 ?
                     (CGFloat)(-_header.font.lfHeight) : 16.0;
    NSFont* font = [NSFont fontWithName:@"PingFang SC" size:fontPt];
    if (!font) font = [NSFont systemFontOfSize:fontPt];
    CTFontRef ctFont = (__bridge CTFontRef)font;
    CGFloat ascent = CTFontGetAscent(ctFont);

    // 按 Page 引擎计算的字符坐标逐字符绘制：layout 与 render 完全一致，
    // 右边距严格等于 internal_border.right。
    int y = TOP_MIN;
    for (int i = 0; i < pi->lines.used; ++i) {
        const line_info_t& line = pi->lines.lines[i];
        if (line.char_cnt <= 0) {
            y += line.cy + line.gap;
            continue;
        }

        // Skip trailing CR/LF
        int eff = line.char_cnt;
        while (eff > 0) {
            wchar_t c = text[line.chars[eff - 1].idx];
            if (c == 0x0A || c == 0x0D) --eff; else break;
        }
        if (eff <= 0) { y += line.cy + line.gap; continue; }

        // 把字符 → glyphs；非 BMP 字符（>0xFFFF）拆代理对
        std::vector<UniChar> units;
        std::vector<int>     unit2char;  // each UniChar 来自哪个 char_info_t
        units.reserve(eff * 2);
        unit2char.reserve(eff * 2);
        for (int j = 0; j < eff; ++j) {
            uint32_t cp = (uint32_t)text[line.chars[j].idx];
            if (cp <= 0xFFFF) {
                units.push_back((UniChar)cp);
                unit2char.push_back(j);
            } else {
                uint32_t v = cp - 0x10000;
                units.push_back((UniChar)(0xD800 | (v >> 10)));
                units.push_back((UniChar)(0xDC00 | (v & 0x3FF)));
                unit2char.push_back(j);
                unit2char.push_back(j);
            }
        }

        size_t glyphCount = units.size();
        std::vector<CGGlyph> glyphs(glyphCount);
        if (!CTFontGetGlyphsForCharacters(ctFont, units.data(),
                                          glyphs.data(), (CFIndex)glyphCount)) {
            y += line.cy + line.gap;
            continue;
        }

        // 每个 glyph 的 x 坐标 = LEFT_MIN + line.x + (该字符 char.cx 累计前缀和)
        std::vector<int> charX(eff + 1, 0);
        for (int j = 0; j < eff; ++j) {
            charX[j + 1] = charX[j] + line.chars[j].cx + CHAR_GAP;
        }

        std::vector<CGPoint> positions(glyphCount);
        // 反转 y 写到下方再变换；这里 baseline = y + ascent
        CGFloat baseY = (CGFloat)y + ascent;
        for (size_t k = 0; k < glyphCount; ++k) {
            int j = unit2char[k];
            positions[k].x = (CGFloat)(LEFT_MIN + line.x + charX[j]);
            positions[k].y = baseY;
        }

        CGContextSaveGState(ctx);
        // 翻转坐标系：view 是 isFlipped=YES，y 向下增；
        // Core Text 字形需要 y 向上的坐标系，沿 y 镜像一次。
        CGContextScaleCTM(ctx, 1.0, -1.0);
        for (auto& p : positions) p.y = -p.y;
        CTFontDrawGlyphs(ctFont, glyphs.data(), positions.data(),
                         glyphCount, ctx);
        CGContextRestoreGState(ctx);

        y += line.cy + line.gap;
    }
}

@end

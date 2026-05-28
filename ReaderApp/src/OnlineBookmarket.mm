#import "OnlineBookmarket.h"
#import "ReaderCanvasView.h"
#import "reader/html_parser.h"

#import <Foundation/Foundation.h>

// =========================================================================
//                               BookSource
// =========================================================================

@implementation BookSource

+ (instancetype)fromDict:(NSDictionary*)d {
    BookSource* s = [[BookSource alloc] init];
    s.title             = d[@"title"];
    s.host              = d[@"host"];
    s.queryUrl          = d[@"query_url"];
    s.queryMethod       = [d[@"query_method"]   intValue];
    s.queryParams       = d[@"query_params"];
    s.queryCharset      = [d[@"query_charset"]  intValue];
    s.bookNameXpath     = d[@"book_name_xpath"];
    s.bookMainpageXpath = d[@"book_mainpage_xpath"];
    s.bookAuthorXpath   = d[@"book_author_xpath"];
    s.chapterTitleXpath = d[@"chapter_title_xpath"];
    s.chapterUrlXpath   = d[@"chapter_url_xpath"];
    s.contentXpath      = d[@"content_xpath"];
    return s;
}

+ (NSArray<BookSource*>*)bundled {
    NSString* path = [NSBundle.mainBundle pathForResource:@"bs" ofType:@"json"];
    if (!path) return @[];
    NSData* d = [NSData dataWithContentsOfFile:path];
    if (!d) return @[];
    NSDictionary* j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    NSArray* arr = j[@"book_sources"];
    NSMutableArray* out = [NSMutableArray array];
    for (NSDictionary* item in arr) [out addObject:[self fromDict:item]];
    return out;
}
@end

// =========================================================================
//   Helpers：URL 拼接 / 编码处理 / NSURLSession 包装 / XPath 抽取
// =========================================================================

static NSString* gbkOrUtf8Decode(NSData* data, int charset) {
    if (data.length == 0) return @"";
    NSStringEncoding enc = NSUTF8StringEncoding;
    if (charset == 2) {
        enc = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    }
    NSString* s = [[NSString alloc] initWithData:data encoding:enc];
    if (!s) {  // try fallback
        s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return s ?: @"";
}

static NSString* gbkOrUtf8UrlEncode(NSString* keyword, int charset) {
    if (charset == 2) {
        NSStringEncoding gbk = CFStringConvertEncodingToNSStringEncoding(
            kCFStringEncodingGB_18030_2000);
        NSData* d = [keyword dataUsingEncoding:gbk];
        NSMutableString* out = [NSMutableString string];
        const uint8_t* p = (const uint8_t*)d.bytes;
        for (NSUInteger i = 0; i < d.length; ++i) {
            uint8_t c = p[i];
            if ((c >= '0' && c <= '9') ||
                (c >= 'A' && c <= 'Z') ||
                (c >= 'a' && c <= 'z') ||
                c == '-' || c == '_' || c == '.' || c == '~') {
                [out appendFormat:@"%c", c];
            } else {
                [out appendFormat:@"%%%02X", c];
            }
        }
        return out;
    }
    return [keyword stringByAddingPercentEncodingWithAllowedCharacters:
            [NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"";
}

// 把抓到的相对/绝对/协议相对 URL 转成完整 URL
static NSString* absolutize(NSString* href, NSString* base) {
    if (href.length == 0) return @"";
    if ([href hasPrefix:@"http://"] || [href hasPrefix:@"https://"]) return href;
    if ([href hasPrefix:@"//"]) {
        NSURL* baseUrl = [NSURL URLWithString:base];
        return [NSString stringWithFormat:@"%@:%@", baseUrl.scheme, href];
    }
    NSURL* baseUrl = [NSURL URLWithString:base];
    if ([href hasPrefix:@"/"]) {
        return [NSString stringWithFormat:@"%@://%@%@",
                baseUrl.scheme, baseUrl.host, href];
    }
    // 相对路径：在 base 的目录下
    NSURL* combined = [NSURL URLWithString:href relativeToURL:baseUrl];
    return combined.absoluteString ?: @"";
}

// 用 HtmlParser 抽取 XPath 结果（一行 char_array）
static NSArray<NSString*>* xpathAll(NSString* html, NSString* xpath) {
    if (html.length == 0 || xpath.length == 0) return @[];
    NSData* d = [html dataUsingEncoding:NSUTF8StringEncoding];
    std::vector<std::string> out;
    int stop = 0;
    HtmlParser::Instance()->HtmlParseByXpath((const char*)d.bytes, (int)d.length,
                                              std::string(xpath.UTF8String),
                                              out, &stop, 0);
    NSMutableArray* res = [NSMutableArray array];
    for (auto& s : out) {
        [res addObject:[NSString stringWithUTF8String:s.c_str()] ?: @""];
    }
    return res;
}

// 发请求
static void fetchURL(NSString* urlString, int charset,
                     void (^cb)(NSString* body, NSError* err)) {
    NSURL* u = [NSURL URLWithString:urlString];
    if (!u) { cb(nil, [NSError errorWithDomain:@"online" code:1 userInfo:nil]); return; }
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:u];
    req.timeoutInterval = 15.0;
    // 伪装一下 UA 提高存活率
    [req setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0) "
                  @"AppleWebKit/605.1.15 (KHTML, like Gecko) "
                  @"Version/16.0 Safari/605.1.15"
       forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask* t =
    [NSURLSession.sharedSession dataTaskWithRequest:req
                                   completionHandler:^(NSData* data,
                                                       NSURLResponse* resp,
                                                       NSError* err) {
        if (err) { dispatch_async(dispatch_get_main_queue(), ^{ cb(nil, err); }); return; }
        NSString* body = gbkOrUtf8Decode(data, charset);
        dispatch_async(dispatch_get_main_queue(), ^{ cb(body, nil); });
    }];
    [t resume];
}

// =========================================================================
//                    OnlineBookmarketWindowController
// =========================================================================

typedef NS_ENUM(NSInteger, OBState) {
    OBStateSearch = 0,
    OBStateChapters,
};

@interface OnlineBookmarketWindowController () <NSTableViewDataSource,
                                                NSTableViewDelegate>
@property (weak)   ReaderCanvasView* canvas;
@property (strong) NSArray<BookSource*>* sources;
@property (assign) NSInteger        selectedSourceIndex;
@property (assign) OBState          state;
// 搜索结果：[{title, url, author}]
@property (strong) NSMutableArray<NSDictionary*>* searchResults;
// 章节列表：[{title, url}]
@property (strong) NSMutableArray<NSDictionary*>* chapterList;
@property (copy)   NSString*        currentBookTitle;

// UI
@property (strong) NSPopUpButton*  sourcePopup;
@property (strong) NSTextField*    keywordField;
@property (strong) NSButton*       searchButton;
@property (strong) NSButton*       backButton;
@property (strong) NSTextField*    statusLabel;
@property (strong) NSTableView*    table;
@end

@implementation OnlineBookmarketWindowController

- (instancetype)initWithCanvas:(ReaderCanvasView*)canvas {
    NSRect frame = NSMakeRect(0, 0, 620, 480);
    NSWindow* w = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled
                                                         | NSWindowStyleMaskClosable
                                                         | NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    w.title = @"在线小说";
    [w setContentMinSize:NSMakeSize(520, 360)];
    self = [super initWithWindow:w];
    if (self) {
        _canvas = canvas;
        _sources = [BookSource bundled];
        _selectedSourceIndex = 0;
        _searchResults = [NSMutableArray array];
        _chapterList   = [NSMutableArray array];
        _state = OBStateSearch;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    NSView* root = self.window.contentView;

    self.sourcePopup = [[NSPopUpButton alloc] init];
    self.sourcePopup.translatesAutoresizingMaskIntoConstraints = NO;
    for (BookSource* s in self.sources) [self.sourcePopup addItemWithTitle:s.title ?: @""];
    self.sourcePopup.target = self;
    self.sourcePopup.action = @selector(sourceChanged:);
    [root addSubview:self.sourcePopup];

    self.keywordField = [[NSTextField alloc] init];
    self.keywordField.placeholderString = @"输入书名关键词，回车搜索";
    self.keywordField.translatesAutoresizingMaskIntoConstraints = NO;
    self.keywordField.target = self;
    self.keywordField.action = @selector(performSearch:);
    [root addSubview:self.keywordField];

    self.searchButton = [NSButton buttonWithTitle:@"搜索"
                                             target:self
                                             action:@selector(performSearch:)];
    self.searchButton.bezelStyle = NSBezelStyleRounded;
    self.searchButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:self.searchButton];

    self.backButton = [NSButton buttonWithTitle:@"← 搜索结果"
                                           target:self
                                           action:@selector(backToSearch:)];
    self.backButton.bezelStyle = NSBezelStyleRounded;
    self.backButton.hidden = YES;
    self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:self.backButton];

    self.statusLabel = [NSTextField labelWithString:@"选源 → 输入关键词 → 回车搜索"];
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:self.statusLabel];

    NSScrollView* sv = [[NSScrollView alloc] init];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    sv.hasVerticalScroller = YES;
    sv.borderType = NSBezelBorder;

    self.table = [[NSTableView alloc] init];
    self.table.rowHeight = 28;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.doubleAction = @selector(rowDoubleClicked:);
    self.table.target = self;

    NSTableColumn* c1 = [[NSTableColumn alloc] initWithIdentifier:@"col1"];
    c1.title = @"书名 / 章节标题"; c1.width = 360;
    [self.table addTableColumn:c1];
    NSTableColumn* c2 = [[NSTableColumn alloc] initWithIdentifier:@"col2"];
    c2.title = @"作者 / 链接"; c2.width = 220;
    [self.table addTableColumn:c2];
    sv.documentView = self.table;
    [root addSubview:sv];

    [NSLayoutConstraint activateConstraints:@[
        // 顶部一行
        [self.sourcePopup.topAnchor      constraintEqualToAnchor:root.topAnchor constant:14],
        [self.sourcePopup.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:14],
        [self.sourcePopup.widthAnchor    constraintEqualToConstant:180],
        [self.keywordField.centerYAnchor constraintEqualToAnchor:self.sourcePopup.centerYAnchor],
        [self.keywordField.leadingAnchor constraintEqualToAnchor:self.sourcePopup.trailingAnchor constant:10],
        [self.keywordField.trailingAnchor constraintEqualToAnchor:self.searchButton.leadingAnchor constant:-8],
        [self.searchButton.centerYAnchor constraintEqualToAnchor:self.sourcePopup.centerYAnchor],
        [self.searchButton.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],

        // 状态行
        [self.backButton.topAnchor      constraintEqualToAnchor:self.sourcePopup.bottomAnchor constant:10],
        [self.backButton.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:14],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.backButton.trailingAnchor constant:10],
        [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-14],

        // 表格撑满下方
        [sv.topAnchor     constraintEqualToAnchor:self.backButton.bottomAnchor constant:10],
        [sv.leadingAnchor constraintEqualToAnchor:root.leadingAnchor  constant:14],
        [sv.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],
        [sv.bottomAnchor  constraintEqualToAnchor:root.bottomAnchor constant:-14],
    ]];
}

#pragma mark - state machine

- (void)setState:(OBState)st {
    _state = st;
    if (st == OBStateSearch) {
        self.backButton.hidden = YES;
        [self.table.tableColumns[0] setTitle:@"书名"];
        [self.table.tableColumns[1] setTitle:@"作者"];
    } else {
        self.backButton.hidden = NO;
        [self.table.tableColumns[0] setTitle:[NSString stringWithFormat:@"《%@》章节列表",
                                              self.currentBookTitle ?: @""]];
        [self.table.tableColumns[1] setTitle:@"链接"];
    }
    [self.table reloadData];
}

- (void)sourceChanged:(id)sender {
    self.selectedSourceIndex = self.sourcePopup.indexOfSelectedItem;
}

- (BookSource*)currentSource {
    if (self.selectedSourceIndex < 0 ||
        self.selectedSourceIndex >= (NSInteger)self.sources.count) return nil;
    return self.sources[self.selectedSourceIndex];
}

#pragma mark - search

- (void)performSearch:(id)sender {
    BookSource* src = [self currentSource];
    NSString* kw = self.keywordField.stringValue;
    if (!src || kw.length == 0) return;

    self.statusLabel.stringValue = [NSString stringWithFormat:@"正在搜索「%@」…", kw];
    self.searchButton.enabled = NO;

    NSString* encKw = gbkOrUtf8UrlEncode(kw, src.queryCharset);
    NSString* url = [src.queryUrl stringByReplacingOccurrencesOfString:@"%s"
                                                            withString:encKw];

    fetchURL(url, src.queryCharset, ^(NSString* body, NSError* err) {
        self.searchButton.enabled = YES;
        if (err || body.length == 0) {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"搜索失败：%@",
                                            err.localizedDescription ?: @"无响应"];
            return;
        }
        NSArray<NSString*>* names    = xpathAll(body, src.bookNameXpath);
        NSArray<NSString*>* hrefs    = xpathAll(body, src.bookMainpageXpath);
        NSArray<NSString*>* authors  = xpathAll(body, src.bookAuthorXpath);
        [self.searchResults removeAllObjects];
        NSUInteger n = MIN(names.count, hrefs.count);
        for (NSUInteger i = 0; i < n; ++i) {
            [self.searchResults addObject:@{
                @"title":  [self trim:names[i]],
                @"url":    absolutize(hrefs[i], url),
                @"author": i < authors.count ? [self trim:authors[i]] : @"",
            }];
        }
        self.state = OBStateSearch;
        self.statusLabel.stringValue = [NSString stringWithFormat:@"找到 %lu 本，双击进入章节",
                                        (unsigned long)self.searchResults.count];
    });
}

- (NSString*)trim:(NSString*)s {
    return [s stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

#pragma mark - chapter list

- (void)loadChaptersForBookAtIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)self.searchResults.count) return;
    NSDictionary* book = self.searchResults[i];
    BookSource* src = [self currentSource];
    NSString* url = book[@"url"];
    self.currentBookTitle = book[@"title"];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"加载《%@》章节列表…",
                                    self.currentBookTitle];
    fetchURL(url, src.queryCharset, ^(NSString* body, NSError* err) {
        if (err || body.length == 0) {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"加载失败：%@",
                                            err.localizedDescription ?: @"无响应"];
            return;
        }
        NSArray<NSString*>* titles = xpathAll(body, src.chapterTitleXpath);
        NSArray<NSString*>* hrefs  = xpathAll(body, src.chapterUrlXpath);
        [self.chapterList removeAllObjects];
        NSUInteger n = MIN(titles.count, hrefs.count);
        for (NSUInteger k = 0; k < n; ++k) {
            [self.chapterList addObject:@{
                @"title": [self trim:titles[k]],
                @"url":   absolutize(hrefs[k], url),
            }];
        }
        self.state = OBStateChapters;
        self.statusLabel.stringValue = [NSString stringWithFormat:@"共 %lu 章，双击章节阅读",
                                        (unsigned long)self.chapterList.count];
    });
}

- (void)backToSearch:(id)sender {
    self.state = OBStateSearch;
    self.statusLabel.stringValue = [NSString stringWithFormat:@"找到 %lu 本",
                                    (unsigned long)self.searchResults.count];
}

#pragma mark - content

- (void)loadContentForChapterAtIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)self.chapterList.count) return;
    NSDictionary* ch = self.chapterList[i];
    BookSource* src = [self currentSource];
    NSString* url = ch[@"url"];
    NSString* title = ch[@"title"];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"加载章节《%@》…", title];
    fetchURL(url, src.queryCharset, ^(NSString* body, NSError* err) {
        if (err || body.length == 0) {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"加载失败：%@",
                                            err.localizedDescription ?: @"无响应"];
            return;
        }
        NSArray<NSString*>* paras = xpathAll(body, src.contentXpath);
        NSMutableString* full = [NSMutableString string];
        [full appendFormat:@"%@\n\n", title];
        for (NSString* p in paras) {
            NSString* line = [self cleanHtmlText:p];
            if (line.length > 0) {
                [full appendFormat:@"    %@\n", line];   // 首行缩进
            }
        }
        // 写到 tmp 文件并交给主 canvas 像普通 txt 一样打开
        NSString* tmp = [NSTemporaryDirectory()
                          stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"online-%@-%@.txt",
                                   self.currentBookTitle ?: @"book",
                                   title]];
        // 写 UTF-8 with BOM 让我们的 DecodeText 走 utf8 路径
        NSMutableData* d = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
        [d appendData:[full dataUsingEncoding:NSUTF8StringEncoding]];
        [d writeToFile:tmp atomically:YES];

        [self.canvas openFileAtPath:tmp];
        self.canvas.window.title = [NSString stringWithFormat:@"%@ - %@",
                                    self.currentBookTitle ?: @"在线", title];
        [self.window close];
    });
}

- (NSString*)cleanHtmlText:(NSString*)s {
    NSMutableString* m = [s mutableCopy];
    // 替换常见 HTML 实体
    [m replaceOccurrencesOfString:@"&nbsp;" withString:@" "
                          options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"&amp;" withString:@"&"
                          options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"&lt;" withString:@"<"
                          options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"&gt;" withString:@">"
                          options:0 range:NSMakeRange(0, m.length)];
    return [m stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

#pragma mark - table

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tv {
    return self.state == OBStateSearch
        ? (NSInteger)self.searchResults.count
        : (NSInteger)self.chapterList.count;
}

- (id)tableView:(NSTableView*)tv
objectValueForTableColumn:(NSTableColumn*)col
            row:(NSInteger)row {
    NSArray* arr = self.state == OBStateSearch ? self.searchResults : self.chapterList;
    if (row < 0 || row >= (NSInteger)arr.count) return @"";
    NSDictionary* item = arr[row];
    if ([col.identifier isEqualToString:@"col1"]) return item[@"title"] ?: @"";
    if (self.state == OBStateSearch) return item[@"author"] ?: @"";
    return item[@"url"] ?: @"";
}

- (void)rowDoubleClicked:(id)sender {
    NSInteger row = self.table.clickedRow;
    if (row < 0) return;
    if (self.state == OBStateSearch) [self loadChaptersForBookAtIndex:row];
    else                              [self loadContentForChapterAtIndex:row];
}

@end

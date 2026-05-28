#import "OnlineBookmarket.h"
#import "ReaderCanvasView.h"
#import "reader/html_parser.h"

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

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
    s.enableContentNext       = [d[@"enable_content_next"] intValue];
    s.contentNextUrlXpath     = d[@"content_next_url_xpath"];
    s.contentNextKeywordXpath = d[@"content_next_keyword_xpath"];
    s.contentNextKeyword      = d[@"content_next_keyword"];
    return s;
}

- (NSDictionary*)toDict {
    return @{
        @"title": self.title ?: @"",
        @"host": self.host ?: @"",
        @"query_url": self.queryUrl ?: @"",
        @"query_method": @(self.queryMethod),
        @"query_params": self.queryParams ?: @"",
        @"query_charset": @(self.queryCharset),
        @"book_name_xpath":     self.bookNameXpath ?: @"",
        @"book_mainpage_xpath": self.bookMainpageXpath ?: @"",
        @"book_author_xpath":   self.bookAuthorXpath ?: @"",
        @"chapter_title_xpath": self.chapterTitleXpath ?: @"",
        @"chapter_url_xpath":   self.chapterUrlXpath ?: @"",
        @"content_xpath":       self.contentXpath ?: @"",
        @"enable_content_next":       @(self.enableContentNext),
        @"content_next_url_xpath":     self.contentNextUrlXpath ?: @"",
        @"content_next_keyword_xpath": self.contentNextKeywordXpath ?: @"",
        @"content_next_keyword":       self.contentNextKeyword ?: @"",
    };
}

+ (NSArray<BookSource*>*)bundled {
    return [BookSourceStore.shared all];
}
@end

// =========================================================================
//                           BookSourceStore
// =========================================================================
//
// 数据合并：先读 bundle 自带 bs.json（默认源，可能为空），
// 然后追加 NSUserDefaults 里用户自定义的源。
// 增删改只影响用户自定义集合，写回 NSUserDefaults。

static NSString* const kUserSourcesKey = @"customBookSources";

@interface BookSourceStore ()
@property (strong) NSMutableArray<BookSource*>* sources;
@end

@implementation BookSourceStore

+ (instancetype)shared {
    static BookSourceStore* s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[BookSourceStore alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _sources = [NSMutableArray array];
        [self reload];
    }
    return self;
}

- (void)reload {
    [self.sources removeAllObjects];
    // bundle 默认
    NSString* path = [NSBundle.mainBundle pathForResource:@"bs" ofType:@"json"];
    if (path) {
        NSData* d = [NSData dataWithContentsOfFile:path];
        if (d) {
            NSDictionary* j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            for (NSDictionary* item in (NSArray*)j[@"book_sources"]) {
                [self.sources addObject:[BookSource fromDict:item]];
            }
        }
    }
    // 用户自定义
    NSArray* arr = [NSUserDefaults.standardUserDefaults arrayForKey:kUserSourcesKey];
    for (NSDictionary* item in arr) {
        [self.sources addObject:[BookSource fromDict:item]];
    }
}

- (NSArray<BookSource*>*)all { return [self.sources copy]; }

- (void)persistUserSources {
    // 跳过 bundle 默认源（前 N 条）
    NSString* path = [NSBundle.mainBundle pathForResource:@"bs" ofType:@"json"];
    NSInteger bundledN = 0;
    if (path) {
        NSData* d = [NSData dataWithContentsOfFile:path];
        if (d) {
            NSDictionary* j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            bundledN = [(NSArray*)j[@"book_sources"] count];
        }
    }
    NSMutableArray* out = [NSMutableArray array];
    for (NSInteger i = bundledN; i < (NSInteger)self.sources.count; ++i) {
        [out addObject:[self.sources[i] toDict]];
    }
    [NSUserDefaults.standardUserDefaults setObject:out forKey:kUserSourcesKey];
}

- (void)addSource:(BookSource*)s {
    [self.sources addObject:s];
    [self persistUserSources];
}
- (void)updateAtIndex:(NSInteger)i with:(BookSource*)s {
    if (i < 0 || i >= (NSInteger)self.sources.count) return;
    self.sources[i] = s;
    [self persistUserSources];
}
- (void)removeAtIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)self.sources.count) return;
    [self.sources removeObjectAtIndex:i];
    [self persistUserSources];
}

- (BOOL)importFromFile:(NSString*)filePath replaceAll:(BOOL)replace {
    NSData* d = [NSData dataWithContentsOfFile:filePath];
    if (!d) return NO;
    NSDictionary* j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    NSArray* arr = j[@"book_sources"];
    if (!arr) return NO;
    if (replace) {
        [self.sources removeAllObjects];
    }
    for (NSDictionary* item in arr) {
        [self.sources addObject:[BookSource fromDict:item]];
    }
    [self persistUserSources];
    return YES;
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
@property (strong) NSButton*       manageButton;
@property (strong) NSButton*       backButton;
@property (strong) NSTextField*    statusLabel;
@property (strong) NSTableView*    table;
// 书源管理
@property (strong) NSWindow*       managerWindow;
@property (strong) NSWindow*       managerOwnedWindow;
@property (strong) NSTableView*    managerTable;
- (NSObject*)makeDataSourceForSources:(NSMutableArray<BookSource*>* (^)(void))loader
                                table:(NSTableView*)tbl;
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
        [self refreshSourcesPopup];
    }
    return self;
}

- (void)buildUI {
    NSView* root = self.window.contentView;

    self.sourcePopup = [[NSPopUpButton alloc] init];
    self.sourcePopup.translatesAutoresizingMaskIntoConstraints = NO;
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

    NSButton* manageBtn = [NSButton buttonWithTitle:@"管理书源…"
                                                target:self
                                                action:@selector(showSourceManager:)];
    manageBtn.bezelStyle = NSBezelStyleRounded;
    manageBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:manageBtn];
    self.manageButton = manageBtn;

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
        [self.searchButton.trailingAnchor constraintEqualToAnchor:self.manageButton.leadingAnchor constant:-8],
        [self.manageButton.centerYAnchor constraintEqualToAnchor:self.sourcePopup.centerYAnchor],
        [self.manageButton.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],

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

- (void)refreshSourcesPopup {
    [self.sourcePopup removeAllItems];
    self.sources = [BookSource bundled];
    if (self.sources.count == 0) {
        [self.sourcePopup addItemWithTitle:@"（暂无书源，点 管理书源…）"];
        self.searchButton.enabled = NO;
        self.keywordField.enabled = NO;
        self.statusLabel.stringValue = @"点击右上「管理书源…」按钮添加或导入书源";
    } else {
        for (BookSource* s in self.sources) [self.sourcePopup addItemWithTitle:s.title ?: @""];
        self.searchButton.enabled = YES;
        self.keywordField.enabled = YES;
        if (self.selectedSourceIndex >= (NSInteger)self.sources.count) {
            self.selectedSourceIndex = 0;
        }
        [self.sourcePopup selectItemAtIndex:self.selectedSourceIndex];
    }
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

// ---------- 章节缓存目录 ----------
static NSString* cachePath(NSString* bookTitle, NSString* chapterTitle) {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString* base = [paths.firstObject stringByAppendingPathComponent:
                      @"MoyuShutan/online"];
    [NSFileManager.defaultManager createDirectoryAtPath:base
                            withIntermediateDirectories:YES
                                             attributes:nil error:nil];
    // 用 path-safe 文件名（去 / 等危险字符）
    NSCharacterSet* bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    NSString* safeBook = [[bookTitle componentsSeparatedByCharactersInSet:bad]
                            componentsJoinedByString:@"_"];
    NSString* safeCh = [[chapterTitle componentsSeparatedByCharactersInSet:bad]
                          componentsJoinedByString:@"_"];
    NSString* dir = [base stringByAppendingPathComponent:safeBook ?: @"unknown"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir
                            withIntermediateDirectories:YES
                                             attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.txt", safeCh ?: @"chapter"]];
}

- (void)loadContentForChapterAtIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)self.chapterList.count) return;
    NSDictionary* ch = self.chapterList[i];
    BookSource* src = [self currentSource];
    NSString* url = ch[@"url"];
    NSString* title = ch[@"title"];

    // 本地缓存命中：直接打开
    NSString* cached = cachePath(self.currentBookTitle, title);
    if ([NSFileManager.defaultManager fileExistsAtPath:cached]) {
        [self.canvas openFileAtPath:cached];
        self.canvas.window.title = [NSString stringWithFormat:@"%@ - %@",
                                    self.currentBookTitle ?: @"在线", title];
        self.statusLabel.stringValue = @"（已从本地缓存载入）";
        [self.window close];
        return;
    }

    self.statusLabel.stringValue = [NSString stringWithFormat:@"加载章节《%@》…", title];
    NSMutableString* full = [NSMutableString string];
    [full appendFormat:@"%@\n\n", title];
    [self fetchChapterPage:url source:src accumInto:full pageNum:1
                completion:^{
        // 写到缓存目录
        NSMutableData* d = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
        [d appendData:[full dataUsingEncoding:NSUTF8StringEncoding]];
        [d writeToFile:cached atomically:YES];

        [self.canvas openFileAtPath:cached];
        self.canvas.window.title = [NSString stringWithFormat:@"%@ - %@",
                                    self.currentBookTitle ?: @"在线", title];
        [self.window close];
    }];
}

// 递归抓取一页内容；如果 enable_content_next 且找到下一页链接，继续抓拼接
- (void)fetchChapterPage:(NSString*)url
                   source:(BookSource*)src
                accumInto:(NSMutableString*)full
                  pageNum:(int)pn
               completion:(void (^)(void))done {
    if (pn > 20) { done(); return; }  // 安全上限
    self.statusLabel.stringValue = [NSString stringWithFormat:@"抓取第 %d 页…", pn];
    fetchURL(url, src.queryCharset, ^(NSString* body, NSError* err) {
        if (err || body.length == 0) { done(); return; }
        NSArray<NSString*>* paras = xpathAll(body, src.contentXpath);
        for (NSString* p in paras) {
            NSString* line = [self cleanHtmlText:p];
            if (line.length > 0) {
                [full appendFormat:@"    %@\n", line];
            }
        }
        if (src.enableContentNext &&
            src.contentNextUrlXpath.length > 0 &&
            src.contentNextKeyword.length > 0) {
            // 检查下一页按钮文字是否匹配关键字
            NSArray<NSString*>* nextKeywords = src.contentNextKeywordXpath.length > 0
                ? xpathAll(body, src.contentNextKeywordXpath)
                : @[];
            NSArray<NSString*>* nextUrls = xpathAll(body, src.contentNextUrlXpath);
            BOOL match = NO;
            for (NSString* k in nextKeywords) {
                if ([[self trim:k] rangeOfString:src.contentNextKeyword].location != NSNotFound) {
                    match = YES; break;
                }
            }
            // 没有关键字检查时直接看 url 是否变了
            if (match && nextUrls.count > 0) {
                NSString* next = absolutize(nextUrls.firstObject, url);
                if (next.length > 0 && ![next isEqualToString:url]) {
                    [self fetchChapterPage:next source:src accumInto:full
                                   pageNum:pn + 1 completion:done];
                    return;
                }
            }
        }
        done();
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

#pragma mark - 书源管理

- (void)showSourceManager:(id)sender {
    NSWindow* w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 540, 420)
                                              styleMask:(NSWindowStyleMaskTitled
                                                         | NSWindowStyleMaskClosable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    w.title = @"书源管理";

    NSView* root = w.contentView;
    NSScrollView* sv = [[NSScrollView alloc] init];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    sv.hasVerticalScroller = YES;
    sv.borderType = NSBezelBorder;

    NSTableView* tbl = [[NSTableView alloc] init];
    tbl.rowHeight = 26;
    tbl.usesAlternatingRowBackgroundColors = YES;
    NSTableColumn* c1 = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    c1.title = @"书源名称"; c1.width = 200;
    [tbl addTableColumn:c1];
    NSTableColumn* c2 = [[NSTableColumn alloc] initWithIdentifier:@"host"];
    c2.title = @"站点"; c2.width = 280;
    [tbl addTableColumn:c2];
    sv.documentView = tbl;
    [root addSubview:sv];

    NSButton* addBtn  = [NSButton buttonWithTitle:@"+ 添加"
                                              target:nil action:nil];
    NSButton* editBtn = [NSButton buttonWithTitle:@"编辑"
                                              target:nil action:nil];
    NSButton* delBtn  = [NSButton buttonWithTitle:@"删除"
                                              target:nil action:nil];
    NSButton* impBtn  = [NSButton buttonWithTitle:@"从文件导入…"
                                              target:nil action:nil];
    for (NSButton* b in @[addBtn, editBtn, delBtn, impBtn]) {
        b.translatesAutoresizingMaskIntoConstraints = NO;
        [root addSubview:b];
    }

    __weak typeof(self) ws = self;
    __weak NSTableView*  wtbl = tbl;
    NSMutableArray<BookSource*>* (^loadAll)(void) = ^{
        return [[BookSourceStore.shared all] mutableCopy];
    };

    // 表格 data source 用 block-backed object
    static __strong id dsHolder = nil;
    NSObject* ds = [self makeDataSourceForSources:loadAll table:tbl];
    dsHolder = ds;
    tbl.dataSource = (id)ds;
    tbl.delegate   = (id)ds;
    [tbl reloadData];

    addBtn.target = self; addBtn.action = @selector(addSourceClicked:);
    editBtn.target = self; editBtn.action = @selector(editSourceClicked:);
    delBtn.target = self; delBtn.action = @selector(deleteSourceClicked:);
    impBtn.target = self; impBtn.action = @selector(importSourcesClicked:);
    self.managerTable = tbl;
    self.managerWindow = w;

    [NSLayoutConstraint activateConstraints:@[
        [sv.topAnchor      constraintEqualToAnchor:root.topAnchor constant:14],
        [sv.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:14],
        [sv.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],
        [sv.bottomAnchor   constraintEqualToAnchor:addBtn.topAnchor constant:-12],

        [addBtn.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:14],
        [addBtn.bottomAnchor   constraintEqualToAnchor:root.bottomAnchor constant:-14],
        [editBtn.leadingAnchor constraintEqualToAnchor:addBtn.trailingAnchor constant:8],
        [editBtn.centerYAnchor constraintEqualToAnchor:addBtn.centerYAnchor],
        [delBtn.leadingAnchor  constraintEqualToAnchor:editBtn.trailingAnchor constant:8],
        [delBtn.centerYAnchor  constraintEqualToAnchor:addBtn.centerYAnchor],
        [impBtn.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],
        [impBtn.centerYAnchor  constraintEqualToAnchor:addBtn.centerYAnchor],
    ]];

    [w center];
    [w makeKeyAndOrderFront:nil];
    self.managerOwnedWindow = w;  // 保活
    (void)ws;
    (void)wtbl;
}

// 简易 data source（包装在 NSObject 里实现协议）
- (NSObject*)makeDataSourceForSources:(NSMutableArray<BookSource*>* (^)(void))loader
                                table:(NSTableView*)tbl {
    Class cls = NSClassFromString(@"_OBMSourcesDataSource");
    if (!cls) {
        cls = objc_allocateClassPair([NSObject class], "_OBMSourcesDataSource", 0);
        class_addProtocol(cls, @protocol(NSTableViewDataSource));
        class_addProtocol(cls, @protocol(NSTableViewDelegate));
        class_addMethod(cls, @selector(numberOfRowsInTableView:),
            imp_implementationWithBlock(^NSInteger(id self_, NSTableView* tv) {
                return (NSInteger)[BookSourceStore.shared all].count;
            }), "q@:@");
        class_addMethod(cls, @selector(tableView:objectValueForTableColumn:row:),
            imp_implementationWithBlock(^id(id self_, NSTableView* tv,
                                            NSTableColumn* col, NSInteger row) {
                NSArray<BookSource*>* arr = [BookSourceStore.shared all];
                if (row < 0 || row >= (NSInteger)arr.count) return @"";
                BookSource* s = arr[row];
                if ([col.identifier isEqualToString:@"title"]) return s.title ?: @"";
                return s.host ?: @"";
            }), "@@:@@q");
        objc_registerClassPair(cls);
    }
    return [[cls alloc] init];
}

- (void)addSourceClicked:(id)sender {
    [self editSource:nil index:-1];
}

- (void)editSourceClicked:(id)sender {
    NSInteger row = self.managerTable.selectedRow;
    if (row < 0) return;
    NSArray<BookSource*>* arr = [BookSourceStore.shared all];
    [self editSource:arr[row] index:row];
}

- (void)deleteSourceClicked:(id)sender {
    NSInteger row = self.managerTable.selectedRow;
    if (row < 0) return;
    NSAlert* a = [[NSAlert alloc] init];
    a.messageText = @"删除该书源？";
    a.informativeText = [BookSourceStore.shared all][row].title ?: @"";
    [a addButtonWithTitle:@"删除"];
    [a addButtonWithTitle:@"取消"];
    if ([a runModal] == NSAlertFirstButtonReturn) {
        [BookSourceStore.shared removeAtIndex:row];
        [self.managerTable reloadData];
        [self refreshSourcesPopup];
    }
}

- (void)importSourcesClicked:(id)sender {
    NSOpenPanel* p = [NSOpenPanel openPanel];
    p.allowedFileTypes = @[@"json"];
    p.title = @"导入 bs.json 书源配置";
    if ([p runModal] != NSModalResponseOK) return;
    NSAlert* mode = [[NSAlert alloc] init];
    mode.messageText = @"导入方式";
    mode.informativeText = @"追加：保留现有书源，添加文件中的源\n覆盖：清空后只保留文件中的源";
    [mode addButtonWithTitle:@"追加"];
    [mode addButtonWithTitle:@"覆盖"];
    [mode addButtonWithTitle:@"取消"];
    NSModalResponse r = [mode runModal];
    if (r == NSAlertThirdButtonReturn) return;
    BOOL replace = (r == NSAlertSecondButtonReturn);
    BOOL ok = [BookSourceStore.shared importFromFile:p.URL.path replaceAll:replace];
    if (!ok) {
        NSAlert* err = [[NSAlert alloc] init];
        err.messageText = @"导入失败";
        err.informativeText = @"文件格式不对，应为 {\"book_sources\":[...]} 结构";
        [err runModal];
        return;
    }
    [self.managerTable reloadData];
    [self refreshSourcesPopup];
}

- (void)editSource:(BookSource*)existing index:(NSInteger)idx {
    NSAlert* a = [[NSAlert alloc] init];
    a.messageText = existing ? @"编辑书源" : @"添加书源";
    a.informativeText = @"按提示填写各 XPath；查询 URL 中 %s 是关键词占位符。";
    [a addButtonWithTitle:@"保存"];
    [a addButtonWithTitle:@"取消"];

    // 简易表单：用 NSStackView 包多个 textfield
    NSView* form = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 460, 380)];
    NSArray<NSString*>* labels = @[
        @"名称", @"站点 host", @"查询 URL（含 %s）",
        @"字符编码 (1=UTF8, 2=GBK)",
        @"书名 XPath", @"主页 XPath", @"作者 XPath",
        @"章节标题 XPath", @"章节链接 XPath", @"正文 XPath",
    ];
    NSMutableArray<NSTextField*>* fields = [NSMutableArray array];
    CGFloat y = 350;
    for (NSString* lab in labels) {
        NSTextField* l = [NSTextField labelWithString:lab];
        l.frame = NSMakeRect(0, y, 130, 22);
        l.alignment = NSTextAlignmentRight;
        [form addSubview:l];
        NSTextField* tf = [[NSTextField alloc] initWithFrame:NSMakeRect(140, y - 2, 310, 24)];
        [form addSubview:tf];
        [fields addObject:tf];
        y -= 32;
    }
    if (existing) {
        fields[0].stringValue = existing.title             ?: @"";
        fields[1].stringValue = existing.host              ?: @"";
        fields[2].stringValue = existing.queryUrl          ?: @"";
        fields[3].stringValue = [NSString stringWithFormat:@"%d", existing.queryCharset ?: 1];
        fields[4].stringValue = existing.bookNameXpath     ?: @"";
        fields[5].stringValue = existing.bookMainpageXpath ?: @"";
        fields[6].stringValue = existing.bookAuthorXpath   ?: @"";
        fields[7].stringValue = existing.chapterTitleXpath ?: @"";
        fields[8].stringValue = existing.chapterUrlXpath   ?: @"";
        fields[9].stringValue = existing.contentXpath      ?: @"";
    } else {
        fields[3].stringValue = @"1";
    }
    a.accessoryView = form;
    if ([a runModal] != NSAlertFirstButtonReturn) return;

    BookSource* s = [[BookSource alloc] init];
    s.title             = fields[0].stringValue;
    s.host              = fields[1].stringValue;
    s.queryUrl          = fields[2].stringValue;
    s.queryMethod       = 0;
    s.queryCharset      = fields[3].stringValue.intValue;
    s.bookNameXpath     = fields[4].stringValue;
    s.bookMainpageXpath = fields[5].stringValue;
    s.bookAuthorXpath   = fields[6].stringValue;
    s.chapterTitleXpath = fields[7].stringValue;
    s.chapterUrlXpath   = fields[8].stringValue;
    s.contentXpath      = fields[9].stringValue;
    if (existing) [BookSourceStore.shared updateAtIndex:idx with:s];
    else          [BookSourceStore.shared addSource:s];

    [self.managerTable reloadData];
    [self refreshSourcesPopup];
}

@end

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
    s.title              = d[@"title"];
    s.host               = d[@"host"];
    s.queryUrl           = d[@"query_url"];
    s.queryMethod        = [d[@"query_method"]   intValue];
    s.queryParams        = d[@"query_params"];
    s.queryCharset       = [d[@"query_charset"]  intValue];
    s.bookNameXpath      = d[@"book_name_xpath"];
    s.bookMainpageXpath  = d[@"book_mainpage_xpath"];
    s.bookAuthorXpath    = d[@"book_author_xpath"];
    s.chapterListUrlFrom = d[@"chapter_list_url_from"];
    s.chapterListUrlTo   = d[@"chapter_list_url_to"];
    s.chapterTitleXpath  = d[@"chapter_title_xpath"];
    s.chapterUrlXpath    = d[@"chapter_url_xpath"];
    s.contentXpath       = d[@"content_xpath"];
    s.enableContentNext       = [d[@"enable_content_next"] intValue];
    s.contentNextUrlXpath     = d[@"content_next_url_xpath"];
    s.contentNextKeywordXpath = d[@"content_next_keyword_xpath"];
    s.contentNextKeyword      = d[@"content_next_keyword"];
    return s;
}

+ (NSArray<BookSource*>*)allSources {
    static NSArray<BookSource*>* cached = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray* arr = [NSMutableArray array];
        NSString* path = [NSBundle.mainBundle pathForResource:@"bs" ofType:@"json"];
        if (path) {
            NSData* d = [NSData dataWithContentsOfFile:path];
            if (d) {
                NSDictionary* j = [NSJSONSerialization JSONObjectWithData:d
                                                                  options:0 error:nil];
                for (NSDictionary* item in (NSArray*)j[@"book_sources"]) {
                    [arr addObject:[BookSource fromDict:item]];
                }
            }
        }
        cached = [arr copy];
    });
    return cached;
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
    if (!s) s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
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
    NSURL* combined = [NSURL URLWithString:href relativeToURL:baseUrl];
    return combined.absoluteString ?: @"";
}

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

static NSString* cleanHtmlText(NSString* s) {
    NSMutableString* m = [s mutableCopy];
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

// HTTP 请求（支持 GET / POST，自动按 charset 解码，completion 投递到主队列）
static void fetchURL(NSString* urlString,
                     NSString* postBody,
                     int charset,
                     void (^cb)(NSString* body, NSError* err)) {
    NSURL* u = [NSURL URLWithString:urlString];
    if (!u) {
        dispatch_async(dispatch_get_main_queue(), ^{
            cb(nil, [NSError errorWithDomain:@"online" code:1 userInfo:nil]);
        });
        return;
    }
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:u];
    req.timeoutInterval = 20.0;
    [req setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0) "
                  @"AppleWebKit/605.1.15 (KHTML, like Gecko) "
                  @"Version/16.0 Safari/605.1.15"
       forHTTPHeaderField:@"User-Agent"];
    if (postBody.length > 0) {
        req.HTTPMethod = @"POST";
        [req setValue:@"application/x-www-form-urlencoded"
           forHTTPHeaderField:@"Content-Type"];
        req.HTTPBody = [postBody dataUsingEncoding:NSUTF8StringEncoding];
    }
    NSURLSessionDataTask* t =
    [NSURLSession.sharedSession dataTaskWithRequest:req
                                   completionHandler:^(NSData* data,
                                                       NSURLResponse* resp,
                                                       NSError* err) {
        if (err) {
            dispatch_async(dispatch_get_main_queue(), ^{ cb(nil, err); });
            return;
        }
        NSString* body = gbkOrUtf8Decode(data, charset);
        dispatch_async(dispatch_get_main_queue(), ^{ cb(body, nil); });
    }];
    [t resume];
}

// 递归抓取一页内容；如果 enable_content_next 且找到下一页链接，继续抓拼接
static void fetchChapterPageRecursive(NSString* url, BookSource* src,
                                       NSMutableString* full, int pn,
                                       void (^onDone)(void)) {
    if (pn > 20) { if (onDone) onDone(); return; }
    fetchURL(url, nil, src.queryCharset, ^(NSString* body, NSError* err) {
        if (err || body.length == 0) { if (onDone) onDone(); return; }
        NSArray<NSString*>* paras = xpathAll(body, src.contentXpath);
        for (NSString* p in paras) {
            NSString* line = cleanHtmlText(p);
            if (line.length > 0) [full appendFormat:@"    %@\n", line];
        }
        if (src.enableContentNext &&
            src.contentNextUrlXpath.length > 0 &&
            src.contentNextKeyword.length > 0) {
            NSArray<NSString*>* nextKeywords = src.contentNextKeywordXpath.length > 0
                ? xpathAll(body, src.contentNextKeywordXpath) : @[];
            NSArray<NSString*>* nextUrls = xpathAll(body, src.contentNextUrlXpath);
            BOOL match = NO;
            for (NSString* k in nextKeywords) {
                NSString* tk = [k stringByTrimmingCharactersInSet:
                                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([tk rangeOfString:src.contentNextKeyword].location != NSNotFound) {
                    match = YES; break;
                }
            }
            if (match && nextUrls.count > 0) {
                NSString* next = absolutize(nextUrls.firstObject, url);
                if (next.length > 0 && ![next isEqualToString:url]) {
                    fetchChapterPageRecursive(next, src, full, pn + 1, onDone);
                    return;
                }
            }
        }
        if (onDone) onDone();
    });
}

// =========================================================================
//   整本书本地路径
// =========================================================================

static NSString* fullBookLocalPath(NSString* bookTitle) {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString* base = [paths.firstObject stringByAppendingPathComponent:
                      @"MoyuShutan/books"];
    [NSFileManager.defaultManager createDirectoryAtPath:base
                            withIntermediateDirectories:YES
                                             attributes:nil error:nil];
    NSCharacterSet* bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    NSString* safe = [[bookTitle componentsSeparatedByCharactersInSet:bad]
                         componentsJoinedByString:@"_"];
    return [base stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.txt", safe ?: @"unknown"]];
}

// =========================================================================
//                       OnlineBookmarketMeta
// =========================================================================

@implementation OnlineBookmarketMeta

+ (BOOL)isOnlineBookPath:(NSString*)path {
    if (path.length == 0) return NO;
    return [path containsString:@"/MoyuShutan/books/"];
}

+ (NSString*)bookTitleFromPath:(NSString*)path {
    if (![self isOnlineBookPath:path]) return nil;
    return path.lastPathComponent.stringByDeletingPathExtension;
}
@end

// =========================================================================
//                    OnlineBookmarketWindowController
// =========================================================================

@interface OnlineBookmarketWindowController () <NSTableViewDataSource,
                                                NSTableViewDelegate>
@property (weak)   ReaderCanvasView* canvas;

// 搜索结果（聚合多源）：[{title, url, author, source(BookSource*)}]
@property (strong) NSMutableArray<NSDictionary*>* searchResults;

// 全源搜索状态
@property (assign) NSInteger        searchInFlight;
@property (copy)   NSString*        searchKeyword;

// 当前下载任务
@property (assign) BOOL             downloading;
@property (assign) BOOL             cancelled;
@property (assign) NSInteger        dlCompleted;
@property (assign) NSInteger        dlTotal;
@property (copy)   NSString*        dlBookTitle;
@property (strong) NSMutableArray*  dlSlots;  // 章节正文 slot 数组

// UI
@property (strong) NSTextField*       keywordField;
@property (strong) NSButton*          searchButton;
@property (strong) NSTextField*       statusLabel;
@property (strong) NSProgressIndicator* progressBar;
@property (strong) NSButton*          cancelButton;
@property (strong) NSTableView*       table;
@end

@implementation OnlineBookmarketWindowController

- (instancetype)initWithCanvas:(ReaderCanvasView*)canvas {
    NSRect frame = NSMakeRect(0, 0, 720, 520);
    NSWindow* w = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled
                                                         | NSWindowStyleMaskClosable
                                                         | NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    w.title = @"在线小说";
    [w setContentMinSize:NSMakeSize(600, 420)];
    self = [super initWithWindow:w];
    if (self) {
        _canvas = canvas;
        _searchResults = [NSMutableArray array];
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    NSView* root = self.window.contentView;

    self.keywordField = [[NSTextField alloc] init];
    self.keywordField.placeholderString = @"输入书名或作者，回车搜索";
    self.keywordField.font = [NSFont systemFontOfSize:14];
    self.keywordField.translatesAutoresizingMaskIntoConstraints = NO;
    self.keywordField.target = self;
    self.keywordField.action = @selector(performSearch:);
    [root addSubview:self.keywordField];

    self.searchButton = [NSButton buttonWithTitle:@"搜索"
                                             target:self
                                             action:@selector(performSearch:)];
    self.searchButton.bezelStyle = NSBezelStyleRounded;
    self.searchButton.keyEquivalent = @"\r";
    self.searchButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:self.searchButton];

    self.statusLabel = [NSTextField labelWithString:@"输入书名或作者后回车搜索"];
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
    c1.title = @"书名"; c1.width = 480; c1.minWidth = 240;
    [self.table addTableColumn:c1];
    NSTableColumn* c2 = [[NSTableColumn alloc] initWithIdentifier:@"col2"];
    c2.title = @"作者"; c2.width = 200; c2.minWidth = 100;
    [self.table addTableColumn:c2];
    sv.documentView = self.table;
    [root addSubview:sv];

    // 进度条 + 取消（下载时显示）
    self.progressBar = [[NSProgressIndicator alloc] init];
    self.progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressBar.style = NSProgressIndicatorStyleBar;
    self.progressBar.indeterminate = NO;
    self.progressBar.hidden = YES;
    [root addSubview:self.progressBar];

    self.cancelButton = [NSButton buttonWithTitle:@"取消下载"
                                             target:self
                                             action:@selector(cancelDownload:)];
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.cancelButton.hidden = YES;
    [root addSubview:self.cancelButton];

    // 用 LayoutGuide 让"取消按钮"垂直居中于 statusLabel + progressBar 整个 block
    NSLayoutGuide* dlGuide = [[NSLayoutGuide alloc] init];
    [root addLayoutGuide:dlGuide];

    [NSLayoutConstraint activateConstraints:@[
        // 顶部
        [self.keywordField.topAnchor      constraintEqualToAnchor:root.topAnchor constant:14],
        [self.keywordField.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:14],
        [self.keywordField.heightAnchor   constraintEqualToConstant:28],
        [self.keywordField.trailingAnchor constraintEqualToAnchor:self.searchButton.leadingAnchor constant:-8],
        [self.searchButton.centerYAnchor  constraintEqualToAnchor:self.keywordField.centerYAnchor],
        [self.searchButton.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],
        [self.searchButton.widthAnchor    constraintEqualToConstant:80],

        // 状态文字（左上）
        [self.statusLabel.topAnchor      constraintEqualToAnchor:self.keywordField.bottomAnchor constant:10],
        [self.statusLabel.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:14],
        [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.cancelButton.leadingAnchor constant:-12],

        // 进度条（状态下方，左侧到 cancel 之间）
        [self.progressBar.topAnchor      constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:5],
        [self.progressBar.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:14],
        [self.progressBar.trailingAnchor constraintEqualToAnchor:self.cancelButton.leadingAnchor constant:-12],
        [self.progressBar.heightAnchor   constraintEqualToConstant:8],

        // Guide 包裹 status + progress
        [dlGuide.topAnchor    constraintEqualToAnchor:self.statusLabel.topAnchor],
        [dlGuide.bottomAnchor constraintEqualToAnchor:self.progressBar.bottomAnchor],

        // 取消按钮（垂直居中于 guide）
        [self.cancelButton.centerYAnchor  constraintEqualToAnchor:dlGuide.centerYAnchor],
        [self.cancelButton.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],

        // 表格
        [sv.topAnchor      constraintEqualToAnchor:self.progressBar.bottomAnchor constant:10],
        [sv.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor  constant:14],
        [sv.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],
        [sv.bottomAnchor   constraintEqualToAnchor:root.bottomAnchor constant:-14],
    ]];
}

#pragma mark - search（全源并发）

- (void)performSearch:(id)sender {
    if (self.downloading) return;
    NSString* kw = [self.keywordField.stringValue
                    stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (kw.length == 0) return;

    NSArray<BookSource*>* sources = [BookSource allSources];
    if (sources.count == 0) {
        self.statusLabel.stringValue = @"内置书源为空（bs.json 未配置）";
        return;
    }

    [self.searchResults removeAllObjects];
    [self.table reloadData];

    self.searchKeyword = kw;
    self.searchInFlight = (NSInteger)sources.count;
    self.searchButton.enabled = NO;
    self.statusLabel.stringValue = [NSString stringWithFormat:
                                    @"正在搜索「%@」（%lu 个源并发查询）…",
                                    kw, (unsigned long)sources.count];

    for (BookSource* src in sources) {
        [self searchOneSource:src keyword:kw];
    }
}

- (void)searchOneSource:(BookSource*)src keyword:(NSString*)kw {
    NSString* encKw = gbkOrUtf8UrlEncode(kw, src.queryCharset);
    NSString* url = src.queryUrl;
    NSString* postBody = nil;
    if (src.queryMethod == 1) {
        postBody = [src.queryParams stringByReplacingOccurrencesOfString:@"%s"
                                                              withString:encKw];
    } else {
        url = [url stringByReplacingOccurrencesOfString:@"%s" withString:encKw];
    }

    __weak typeof(self) ws = self;
    fetchURL(url, postBody, src.queryCharset, ^(NSString* body, NSError* err) {
        __strong typeof(ws) ss = ws;
        if (!ss) return;
        if (!err && body.length > 0) {
            NSArray<NSString*>* names    = xpathAll(body, src.bookNameXpath);
            NSArray<NSString*>* hrefs    = xpathAll(body, src.bookMainpageXpath);
            NSArray<NSString*>* authors  = xpathAll(body, src.bookAuthorXpath);
            NSUInteger n = MIN(names.count, hrefs.count);
            for (NSUInteger i = 0; i < n; ++i) {
                NSString* title = [ss trim:names[i]];
                if (title.length == 0) continue;
                [ss.searchResults addObject:@{
                    @"title":  title,
                    @"url":    absolutize(hrefs[i], url),
                    @"author": i < authors.count ? [ss trim:authors[i]] : @"",
                    @"source": src,
                }];
            }
            [ss.table reloadData];
        }
        ss.searchInFlight--;
        if (ss.searchInFlight <= 0) {
            ss.searchButton.enabled = YES;
            ss.statusLabel.stringValue = [NSString stringWithFormat:
                @"找到 %lu 条结果，双击下载整本到本地阅读",
                (unsigned long)ss.searchResults.count];
        } else {
            ss.statusLabel.stringValue = [NSString stringWithFormat:
                @"已收集 %lu 条结果，剩 %ld 个源…",
                (unsigned long)ss.searchResults.count,
                (long)ss.searchInFlight];
        }
    });
}

- (NSString*)trim:(NSString*)s {
    return [s stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

#pragma mark - 双击 → 整本下载

- (void)rowDoubleClicked:(id)sender {
    if (self.downloading) return;
    NSInteger row = self.table.clickedRow;
    if (row < 0) return;
    [self downloadFullBookAtIndex:row];
}

// 主流程：抓目录页 → 解析章节列表 → 并发下载所有正文 → 拼装写文件 → 打开
- (void)downloadFullBookAtIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)self.searchResults.count) return;
    NSDictionary* book = self.searchResults[i];
    BookSource* src = book[@"source"];
    NSString* bookUrl = book[@"url"];
    NSString* title = book[@"title"];

    // 缓存命中：直接打开本地
    NSString* localPath = fullBookLocalPath(title);
    if ([NSFileManager.defaultManager fileExistsAtPath:localPath]) {
        [self.canvas openFileAtPath:localPath restoreIndex:0];
        self.canvas.window.title = title;
        [self.window close];
        return;
    }

    // 计算目录页 URL
    NSString* listUrl = bookUrl;
    if (src.chapterListUrlFrom.length > 0 && src.chapterListUrlTo.length > 0) {
        listUrl = [bookUrl stringByReplacingOccurrencesOfString:src.chapterListUrlFrom
                                                     withString:src.chapterListUrlTo];
    }

    self.statusLabel.stringValue = [NSString stringWithFormat:@"正在获取《%@》目录…", title];
    self.searchButton.enabled = NO;

    __weak typeof(self) ws = self;
    fetchURL(listUrl, nil, src.queryCharset, ^(NSString* body, NSError* err) {
        __strong typeof(ws) ss = ws;
        if (!ss) return;
        if (err || body.length == 0) {
            ss.statusLabel.stringValue = [NSString stringWithFormat:@"目录加载失败：%@",
                                          err.localizedDescription ?: @"无响应"];
            ss.searchButton.enabled = YES;
            return;
        }
        NSArray<NSString*>* titles = xpathAll(body, src.chapterTitleXpath);
        NSArray<NSString*>* hrefs  = xpathAll(body, src.chapterUrlXpath);
        NSMutableArray* chapters = [NSMutableArray array];
        NSUInteger n = MIN(titles.count, hrefs.count);
        for (NSUInteger k = 0; k < n; ++k) {
            NSString* t = [ss trim:titles[k]];
            if (t.length == 0) continue;
            [chapters addObject:@{
                @"title": t,
                @"url":   absolutize(hrefs[k], listUrl),
            }];
        }
        if (chapters.count == 0) {
            ss.statusLabel.stringValue = @"未抓到章节链接，XPath 可能失效";
            ss.searchButton.enabled = YES;
            return;
        }
        // 笔趣阁 /newbook/ 的"全部章节"已经是 第1章→第N章 正序；这里不再反转。
        // 之前的反转是按 ul.newchapter / ul.xinchapter 「最新优先」 的错误假设。
        [ss startConcurrentDownload:chapters source:src bookTitle:title
                          localPath:localPath];
    });
}

#pragma mark - 并发下载

- (void)startConcurrentDownload:(NSArray<NSDictionary*>*)chapters
                         source:(BookSource*)src
                      bookTitle:(NSString*)title
                      localPath:(NSString*)localPath {
    self.downloading = YES;
    self.cancelled = NO;
    self.dlCompleted = 0;
    self.dlTotal = (NSInteger)chapters.count;
    self.dlBookTitle = title;
    self.dlSlots = [NSMutableArray arrayWithCapacity:chapters.count];
    for (NSUInteger i = 0; i < chapters.count; ++i) {
        [self.dlSlots addObject:@""];
    }

    self.progressBar.hidden = NO;
    self.progressBar.minValue = 0;
    self.progressBar.maxValue = chapters.count;
    self.progressBar.doubleValue = 0;
    self.cancelButton.hidden = NO;
    self.searchButton.enabled = NO;
    self.keywordField.enabled = NO;
    [self updateProgressLabel];

    // NSURLSession 默认 HTTPMaximumConnectionsPerHost=6，全部 task 一次性下发也行
    // 不过为了状态可控，自己用 OperationQueue 限流
    NSOperationQueue* q = [[NSOperationQueue alloc] init];
    q.maxConcurrentOperationCount = 6;
    q.name = @"online-book-download";

    __weak typeof(self) ws = self;
    for (NSInteger i = 0; i < (NSInteger)chapters.count; ++i) {
        NSDictionary* ch = chapters[i];
        NSInteger idx = i;
        [q addOperationWithBlock:^{
            __strong typeof(ws) ss = ws;
            if (!ss || ss.cancelled) return;
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            NSMutableString* full = [NSMutableString string];
            // 章节标题独占一行 + 双换行，让 TextBook 章节解析能识别
            [full appendFormat:@"\n%@\n\n", ch[@"title"]];
            fetchChapterPageRecursive(ch[@"url"], src, full, 1, ^{
                __strong typeof(ws) ss2 = ws;
                if (ss2 && !ss2.cancelled) {
                    ss2.dlSlots[idx] = full;
                    ss2.dlCompleted++;
                    [ss2 updateProgressLabel];
                    if (ss2.dlCompleted >= ss2.dlTotal) {
                        [ss2 finalizeDownloadToPath:localPath];
                    }
                }
                dispatch_semaphore_signal(sem);
            });
            // 兜底超时（30s）避免某章卡死把整本卡住
            dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW,
                                                       30 * NSEC_PER_SEC));
        }];
    }
}

- (void)updateProgressLabel {
    self.progressBar.doubleValue = self.dlCompleted;
    self.statusLabel.stringValue =
        [NSString stringWithFormat:@"正在下载《%@》：%ld / %ld 章",
         self.dlBookTitle, (long)self.dlCompleted, (long)self.dlTotal];
}

- (void)finalizeDownloadToPath:(NSString*)localPath {
    self.downloading = NO;
    if (self.cancelled) {
        self.statusLabel.stringValue = @"已取消下载";
        [self hideProgressUI];
        return;
    }
    NSMutableString* big = [NSMutableString string];
    [big appendFormat:@"%@\n\n", self.dlBookTitle];  // 书名作为整本顶
    for (NSString* s in self.dlSlots) {
        if (s.length > 0) [big appendString:s];
    }
    NSMutableData* d = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
    [d appendData:[big dataUsingEncoding:NSUTF8StringEncoding]];
    BOOL ok = [d writeToFile:localPath atomically:YES];
    if (!ok) {
        self.statusLabel.stringValue = @"写入本地文件失败";
        [self hideProgressUI];
        return;
    }
    [self hideProgressUI];

    // 用 canvas 打开本地整本，强制从头开始
    [self.canvas openFileAtPath:localPath restoreIndex:0];
    self.canvas.window.title = self.dlBookTitle;
    [self.window close];
}

- (void)hideProgressUI {
    self.progressBar.hidden = YES;
    self.cancelButton.hidden = YES;
    self.searchButton.enabled = YES;
    self.keywordField.enabled = YES;
}

- (void)cancelDownload:(id)sender {
    self.cancelled = YES;
    self.statusLabel.stringValue = @"正在取消…";
}

#pragma mark - table

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tv {
    return (NSInteger)self.searchResults.count;
}

- (id)tableView:(NSTableView*)tv
objectValueForTableColumn:(NSTableColumn*)col
            row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.searchResults.count) return @"";
    NSDictionary* item = self.searchResults[row];
    if ([col.identifier isEqualToString:@"col1"]) return item[@"title"] ?: @"";
    if ([col.identifier isEqualToString:@"col2"]) return item[@"author"] ?: @"";
    return @"";
}

@end

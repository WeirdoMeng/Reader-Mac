// 在线小说面板：搜书 → 看章节 → 看正文 → 喂给主 canvas

#pragma once
#import <AppKit/AppKit.h>

@class ReaderCanvasView;

// 单个书源
@interface BookSource : NSObject
@property (copy) NSString* title;
@property (copy) NSString* host;
@property (copy) NSString* queryUrl;       // 含 %s
@property (assign) int     queryMethod;    // 0=GET, 1=POST
@property (copy) NSString* queryParams;
@property (assign) int     queryCharset;   // 0/1=utf8, 2=gbk
@property (copy) NSString* bookNameXpath;
@property (copy) NSString* bookMainpageXpath;
@property (copy) NSString* bookAuthorXpath;
@property (copy) NSString* chapterTitleXpath;
@property (copy) NSString* chapterUrlXpath;
@property (copy) NSString* contentXpath;
// 内容跨页（一般小说站把一章拆成 1/2/3 页时启用）
@property (assign) int     enableContentNext;
@property (copy) NSString* contentNextUrlXpath;     // 抓"下一页"链接
@property (copy) NSString* contentNextKeywordXpath; // 抓"下一页"按钮文字
@property (copy) NSString* contentNextKeyword;      // 比对关键字（例 "下一页"）

+ (NSArray<BookSource*>*)bundled;          // 从 bs.json 资源 + UserDefaults 加载
- (NSDictionary*)toDict;
+ (instancetype)fromDict:(NSDictionary*)d;
@end

// 书源仓库：增删改查 + 持久化
@interface BookSourceStore : NSObject
+ (instancetype)shared;
- (NSArray<BookSource*>*)all;
- (void)addSource:(BookSource*)s;
- (void)updateAtIndex:(NSInteger)i with:(BookSource*)s;
- (void)removeAtIndex:(NSInteger)i;
- (BOOL)importFromFile:(NSString*)path replaceAll:(BOOL)replace;
@end

@interface OnlineBookmarketWindowController : NSWindowController
- (instancetype)initWithCanvas:(ReaderCanvasView*)canvas;
@end

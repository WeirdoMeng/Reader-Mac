// 在线小说面板：搜书 → 整本下载到本地 → 用本地阅读器打开
//
// 用户视角：只有「搜索框」，没有"书源"概念。
// 双击搜索结果即并发抓取整本书所有章节，拼成单一 .txt 写到
//   ~/Library/Application Support/MoyuShutan/books/<书名>.txt
// 之后所有阅读都是本地行为：自由翻页、全章节目录、最近阅读保留。

#pragma once
#import <AppKit/AppKit.h>

@class ReaderCanvasView;

// 单个书源（内部数据结构，不向用户暴露）
@interface BookSource : NSObject
@property (copy) NSString* title;
@property (copy) NSString* host;
@property (copy) NSString* queryUrl;
@property (assign) int     queryMethod;
@property (copy) NSString* queryParams;
@property (assign) int     queryCharset;
@property (copy) NSString* bookNameXpath;
@property (copy) NSString* bookMainpageXpath;
@property (copy) NSString* bookAuthorXpath;
// 书页 → 目录页的 URL 变换（如笔趣阁 /book/ → /newbook/ 拿全 583 章）
@property (copy) NSString* chapterListUrlFrom;
@property (copy) NSString* chapterListUrlTo;
@property (copy) NSString* chapterTitleXpath;
@property (copy) NSString* chapterUrlXpath;
@property (copy) NSString* contentXpath;
@property (assign) int     enableContentNext;
@property (copy) NSString* contentNextUrlXpath;
@property (copy) NSString* contentNextKeywordXpath;
@property (copy) NSString* contentNextKeyword;

+ (NSArray<BookSource*>*)allSources;
+ (instancetype)fromDict:(NSDictionary*)d;
@end

// 路径识别（被 AppDelegate 用来给最近阅读菜单加 [在线] 标记）
@interface OnlineBookmarketMeta : NSObject
+ (BOOL)isOnlineBookPath:(NSString*)path;
+ (NSString*)bookTitleFromPath:(NSString*)path;
@end

@interface OnlineBookmarketWindowController : NSWindowController
- (instancetype)initWithCanvas:(ReaderCanvasView*)canvas;
@end

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
+ (NSArray<BookSource*>*)bundled;          // 从 bs.json 资源加载
@end

@interface OnlineBookmarketWindowController : NSWindowController
- (instancetype)initWithCanvas:(ReaderCanvasView*)canvas;
@end

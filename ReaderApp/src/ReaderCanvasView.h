// NSView subclass that owns a Book + Page engine and paints the current
// page using Core Text. Implements basic keyboard navigation.

#pragma once

#import <AppKit/AppKit.h>

@interface ReaderCanvasView : NSView

// Open a file (.txt / .epub / .mobi). Returns YES on dispatch (parse is async).
- (BOOL)openFileAtPath:(NSString*)path;
- (BOOL)openFileAtPath:(NSString*)path restoreIndex:(int)idx;
- (void)closeBook;

// Manually trigger layout + redraw (call after the engine fires Redraw event).
- (void)relayoutAndRedraw;

// Progress 0..100
- (double)progress;

// Persistence helpers (NSUserDefaults-backed for now).
- (NSString*)currentPath;
- (int)currentIndex;

// Display setting accessors (apply triggers relayout).
- (int)fontSize;
- (void)setFontSize:(int)pt;
- (int)lineGap;
- (void)setLineGap:(int)px;
- (int)paragraphGap;
- (void)setParagraphGap:(int)px;
- (BOOL)firstLineIndent;
- (void)setFirstLineIndent:(BOOL)on;
- (NSColor*)textColor;
- (void)setTextColor:(NSColor*)c;
- (NSColor*)backgroundColor;
- (void)setBackgroundColor:(NSColor*)c;

// Save/restore the whole display profile.
- (void)loadDisplayProfileFromUserDefaults;
- (void)saveDisplayProfileToUserDefaults;

// Chapters
- (NSArray<NSDictionary*>*)chapters;      // each dict: {title, index}
- (void)jumpToTextIndex:(int)idx;
- (void)jumpToChapterAtListIndex:(int)i;  // 0-based

// Bookmarks (NSUserDefaults-backed, per-file path)
- (NSArray<NSNumber*>*)bookmarks;
- (void)addBookmarkAtCurrentLocation;
- (void)removeBookmarkAtIndex:(int)i;

@end

// NSView subclass that owns a Book + Page engine and paints the current
// page using Core Text. Implements basic keyboard navigation.

#pragma once

#import <AppKit/AppKit.h>

@interface ReaderCanvasView : NSView

// Open a file (.txt / .epub / .mobi). Returns YES on dispatch (parse is async).
- (BOOL)openFileAtPath:(NSString*)path;
- (void)closeBook;

// Manually trigger layout + redraw (call after the engine fires Redraw event).
- (void)relayoutAndRedraw;

// Progress 0..100
- (double)progress;

@end

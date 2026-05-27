#pragma once
#import <AppKit/AppKit.h>

@class ReaderCanvasView;

@interface PreferencesWindowController : NSWindowController
- (instancetype)initWithCanvas:(ReaderCanvasView*)canvas;
@end

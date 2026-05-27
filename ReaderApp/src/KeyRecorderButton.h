// NSButton subclass that records a keyboard shortcut when clicked.
// Click → "请按下新组合…" → next keyDown captured → posted via block.

#pragma once
#import <AppKit/AppKit.h>

@class KBShortcut;

@interface KeyRecorderButton : NSButton
@property (copy) void (^onRecorded)(KBShortcut* shortcut);
- (void)setShortcut:(KBShortcut*)s;
@end

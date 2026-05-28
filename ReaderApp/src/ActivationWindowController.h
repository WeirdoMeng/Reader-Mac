// 激活窗口 + 试用过期拦截覆盖层
//
// ActivationWindowController：完整激活面板（二维码 + 机器码 + key 输入）
// ActivationOverlayView：覆盖在阅读器上的"未激活"提示面板
//
// 用法：
//   [[ActivationWindowController shared] showFromWindow:self.window];

#pragma once
#import <AppKit/AppKit.h>

@interface ActivationWindowController : NSWindowController
+ (instancetype)shared;
- (void)showFromWindow:(NSWindow*)parent;
@end

@interface ActivationOverlayView : NSView
@property (copy) void (^onActivateTapped)(void);
@end

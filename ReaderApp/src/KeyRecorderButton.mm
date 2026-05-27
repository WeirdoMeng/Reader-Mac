#import "KeyRecorderButton.h"
#import "KeyBindings.h"

@interface KeyRecorderButton ()
@property (assign) BOOL recording;
@property (strong) KBShortcut* currentShortcut;
@end

@implementation KeyRecorderButton

- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) {
        self.bezelStyle = NSBezelStyleRounded;
        self.target = self;
        self.action = @selector(toggleRecording:);
        self.title = @"—";
    }
    return self;
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)setShortcut:(KBShortcut*)s {
    self.currentShortcut = s;
    self.title = s ? s.displayString : @"—";
}

- (void)toggleRecording:(id)sender {
    if (self.recording) {
        [self stopRecording];
        return;
    }
    self.recording = YES;
    self.title = @"按下新组合…（Esc 取消）";
    [self.window makeFirstResponder:self];
}

- (void)stopRecording {
    if (!self.recording) return;
    self.recording = NO;
    self.title = self.currentShortcut ? self.currentShortcut.displayString : @"—";
    // 把 first responder 让出去，让普通 keyDown 路由恢复正常
    if (self.window && self.window.firstResponder == self) {
        [self.window makeFirstResponder:nil];
    }
}

- (void)viewWillMoveToWindow:(NSWindow*)newWindow {
    [super viewWillMoveToWindow:newWindow];
    if (!newWindow && self.recording) [self stopRecording];
}

// keyDown 只在 firstResponder == self（即 recording 态）时被分发到这里；
// 普通态下不会拦截任何键盘事件 — 因此方向键翻页永远不会被偷走。
- (void)keyDown:(NSEvent*)event {
    if (!self.recording) { [super keyDown:event]; return; }

    if (event.keyCode == 53 /* Esc */) {
        [self stopRecording];
        return;
    }

    NSEventModifierFlags mods = event.modifierFlags &
        (NSEventModifierFlagCommand | NSEventModifierFlagShift |
         NSEventModifierFlagOption  | NSEventModifierFlagControl);

    BOOL isFn = NO;
    unichar c = event.charactersIgnoringModifiers.length ?
                [event.charactersIgnoringModifiers characterAtIndex:0] : 0;
    if (c >= NSF1FunctionKey && c <= NSF35FunctionKey) isFn = YES;

    if (mods == 0 && !isFn) {
        // 不带任何修饰键的普通字符不接受，避免无意义的快捷键
        NSBeep();
        return;
    }

    NSString* k = event.charactersIgnoringModifiers.lowercaseString;
    if (k.length > 1) k = [k substringToIndex:1];
    KBShortcut* sc = [KBShortcut keyChar:k modifiers:mods];
    [self setShortcut:sc];
    [self stopRecording];
    if (self.onRecorded) self.onRecorded(sc);
}

- (void)flagsChanged:(NSEvent*)event {
    // 录入态吃掉，避免触发其他全局键事件
    if (!self.recording) [super flagsChanged:event];
}

@end

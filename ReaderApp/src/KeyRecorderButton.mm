#import "KeyRecorderButton.h"
#import "KeyBindings.h"

@interface KeyRecorderButton ()
@property (assign) BOOL recording;
@property (strong) KBShortcut* currentShortcut;
@property (strong) id eventMonitor;
@end

@implementation KeyRecorderButton

- (void)dealloc {
    if (self.eventMonitor) {
        [NSEvent removeMonitor:self.eventMonitor];
        self.eventMonitor = nil;
    }
}

- (void)viewWillMoveToWindow:(NSWindow*)newWindow {
    [super viewWillMoveToWindow:newWindow];
    if (!newWindow && self.recording) [self stopRecording];
}

- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) {
        self.bezelStyle = NSBezelStyleRounded;
        self.target = self;
        self.action = @selector(toggleRecording:);
        self.title = @"—";
    }
    return self;
}

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

    __weak typeof(self) ws = self;
    self.eventMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                              handler:^NSEvent* (NSEvent* event) {
        // 仅在录入态且事件发往当前 button 所在窗口时拦截
        if (!ws || !ws.recording) return event;
        if (event.window && event.window != ws.window) return event;
        if (event.keyCode == 53 /* Esc */) {
            [ws stopRecording];
            return nil;
        }
        NSEventModifierFlags mods = event.modifierFlags &
            (NSEventModifierFlagCommand | NSEventModifierFlagShift |
             NSEventModifierFlagOption  | NSEventModifierFlagControl);
        if (mods == 0 && ![ws isFunctionKey:event]) {
            // require some modifier for normal keys (avoid stealing typing)
            return event;
        }
        NSString* k = event.charactersIgnoringModifiers.lowercaseString;
        if (k.length > 1) k = [k substringToIndex:1];
        KBShortcut* sc = [KBShortcut keyChar:k modifiers:mods];
        [ws setShortcut:sc];
        [ws stopRecording];
        if (ws.onRecorded) ws.onRecorded(sc);
        return nil;  // consume
    }];
}

- (BOOL)isFunctionKey:(NSEvent*)e {
    unichar c = e.charactersIgnoringModifiers.length ?
                [e.charactersIgnoringModifiers characterAtIndex:0] : 0;
    return c >= NSF1FunctionKey && c <= NSF35FunctionKey;
}

- (void)stopRecording {
    if (self.eventMonitor) {
        [NSEvent removeMonitor:self.eventMonitor];
        self.eventMonitor = nil;
    }
    self.recording = NO;
    self.title = self.currentShortcut ? self.currentShortcut.displayString : @"—";
}
@end

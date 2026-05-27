#import "GlobalHotkey.h"
#import <Carbon/Carbon.h>

static EventHandlerRef  g_handler  = nullptr;
static EventHotKeyRef   g_hotkey   = nullptr;
static void (^g_block)(void)        = nil;

static OSStatus HotKeyEventHandler(EventHandlerCallRef /*next*/,
                                   EventRef /*event*/,
                                   void* /*userData*/) {
    if (g_block) {
        dispatch_async(dispatch_get_main_queue(), ^{ g_block(); });
    }
    return noErr;
}

@implementation GlobalHotkey

+ (BOOL)registerHotkeyWithBlock:(void (^)(void))block {
    if (g_hotkey) [self unregister];
    g_block = [block copy];

    EventTypeSpec spec = {kEventClassKeyboard, kEventHotKeyPressed};
    OSStatus rc = InstallApplicationEventHandler(&HotKeyEventHandler, 1, &spec,
                                                  nullptr, &g_handler);
    if (rc != noErr) {
        NSLog(@"[GlobalHotkey] InstallApplicationEventHandler failed: %d", (int)rc);
        return NO;
    }

    EventHotKeyID hotKeyID;
    hotKeyID.signature = 'rdrm';
    hotKeyID.id = 1;

    // Ctrl + Option + H —— 避开 macOS 输入法对 Option+字母 的死键捕获
    UInt32 modifierFlags = controlKey | optionKey;
    UInt32 keyCode       = kVK_ANSI_H;

    rc = RegisterEventHotKey(keyCode, modifierFlags,
                             hotKeyID, GetApplicationEventTarget(),
                             0, &g_hotkey);
    if (rc != noErr) {
        NSLog(@"[GlobalHotkey] RegisterEventHotKey failed: %d", (int)rc);
        return NO;
    }
    NSLog(@"[GlobalHotkey] Ctrl+Option+H 注册成功");
    return YES;
}

+ (void)unregister {
    if (g_hotkey)  { UnregisterEventHotKey(g_hotkey); g_hotkey = nullptr; }
    if (g_handler) { RemoveEventHandler(g_handler);   g_handler = nullptr; }
    g_block = nil;
}

@end

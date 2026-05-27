#import "GlobalHotkey.h"
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

static EventHandlerRef  g_handler = nullptr;
static EventHotKeyRef   g_hotkey  = nullptr;
static void (^g_block)(void)       = nil;

static OSStatus HotKeyEventHandler(EventHandlerCallRef /*next*/,
                                   EventRef /*event*/,
                                   void* /*userData*/) {
    if (g_block) {
        dispatch_async(dispatch_get_main_queue(), ^{ g_block(); });
    }
    return noErr;
}

// Map a single Unicode character to a Carbon virtual key code.
static UInt32 carbonKeyCodeForChar(NSString* ch) {
    if (ch.length == 0) return 0;
    unichar c = [ch.lowercaseString characterAtIndex:0];
    // ASCII letters
    static const struct { unichar c; UInt32 vk; } table[] = {
        {'a', kVK_ANSI_A}, {'b', kVK_ANSI_B}, {'c', kVK_ANSI_C}, {'d', kVK_ANSI_D},
        {'e', kVK_ANSI_E}, {'f', kVK_ANSI_F}, {'g', kVK_ANSI_G}, {'h', kVK_ANSI_H},
        {'i', kVK_ANSI_I}, {'j', kVK_ANSI_J}, {'k', kVK_ANSI_K}, {'l', kVK_ANSI_L},
        {'m', kVK_ANSI_M}, {'n', kVK_ANSI_N}, {'o', kVK_ANSI_O}, {'p', kVK_ANSI_P},
        {'q', kVK_ANSI_Q}, {'r', kVK_ANSI_R}, {'s', kVK_ANSI_S}, {'t', kVK_ANSI_T},
        {'u', kVK_ANSI_U}, {'v', kVK_ANSI_V}, {'w', kVK_ANSI_W}, {'x', kVK_ANSI_X},
        {'y', kVK_ANSI_Y}, {'z', kVK_ANSI_Z},
        {'0', kVK_ANSI_0}, {'1', kVK_ANSI_1}, {'2', kVK_ANSI_2}, {'3', kVK_ANSI_3},
        {'4', kVK_ANSI_4}, {'5', kVK_ANSI_5}, {'6', kVK_ANSI_6}, {'7', kVK_ANSI_7},
        {'8', kVK_ANSI_8}, {'9', kVK_ANSI_9},
        {'[', kVK_ANSI_LeftBracket},  {']', kVK_ANSI_RightBracket},
        {',', kVK_ANSI_Comma},        {'.', kVK_ANSI_Period},
        {'/', kVK_ANSI_Slash},        {';', kVK_ANSI_Semicolon},
        {'\'', kVK_ANSI_Quote},       {'\\', kVK_ANSI_Backslash},
        {'-', kVK_ANSI_Minus},        {'=', kVK_ANSI_Equal},
        {'`', kVK_ANSI_Grave},        {' ', kVK_Space},
    };
    for (size_t i = 0; i < sizeof(table) / sizeof(table[0]); ++i) {
        if (table[i].c == c) return table[i].vk;
    }
    return 0;
}

// NSEventModifierFlags → Carbon modifier mask.
static UInt32 carbonModsForNSMods(NSUInteger ns) {
    UInt32 m = 0;
    if (ns & NSEventModifierFlagCommand) m |= cmdKey;
    if (ns & NSEventModifierFlagShift)   m |= shiftKey;
    if (ns & NSEventModifierFlagOption)  m |= optionKey;
    if (ns & NSEventModifierFlagControl) m |= controlKey;
    return m;
}

@implementation GlobalHotkey

+ (BOOL)registerWithKeyChar:(NSString*)keyChar
                  modifiers:(NSUInteger)modifiers
                      block:(void (^)(void))block {
    [self unregister];
    if (!keyChar || keyChar.length == 0 || !block) return NO;
    UInt32 vk = carbonKeyCodeForChar(keyChar);
    if (vk == 0) {
        NSLog(@"[GlobalHotkey] 不支持的字符 '%@'", keyChar);
        return NO;
    }
    UInt32 cm = carbonModsForNSMods(modifiers);
    if (cm == 0) {
        NSLog(@"[GlobalHotkey] 至少需要一个修饰键");
        return NO;
    }

    g_block = [block copy];

    EventTypeSpec spec = {kEventClassKeyboard, kEventHotKeyPressed};
    OSStatus rc = InstallApplicationEventHandler(&HotKeyEventHandler, 1, &spec,
                                                  nullptr, &g_handler);
    if (rc != noErr) {
        NSLog(@"[GlobalHotkey] InstallApplicationEventHandler 失败: %d", (int)rc);
        return NO;
    }

    EventHotKeyID hotKeyID;
    hotKeyID.signature = 'rdrm';
    hotKeyID.id = 1;
    rc = RegisterEventHotKey(vk, cm, hotKeyID,
                             GetApplicationEventTarget(), 0, &g_hotkey);
    if (rc != noErr) {
        NSLog(@"[GlobalHotkey] RegisterEventHotKey 失败: %d (key='%@' mods=0x%lx)",
              (int)rc, keyChar, (unsigned long)modifiers);
        return NO;
    }
    NSLog(@"[GlobalHotkey] 注册成功 (key='%@' mods=0x%lx)",
          keyChar, (unsigned long)modifiers);
    return YES;
}

+ (void)unregister {
    if (g_hotkey)  { UnregisterEventHotKey(g_hotkey); g_hotkey = nullptr; }
    if (g_handler) { RemoveEventHandler(g_handler);   g_handler = nullptr; }
    g_block = nil;
}
@end

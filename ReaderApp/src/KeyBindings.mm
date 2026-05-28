#import "KeyBindings.h"
#import <Carbon/Carbon.h>

NSNotificationName const KeyBindingsDidChangeNotification =
    @"KeyBindingsDidChangeNotification";

#pragma mark - KBShortcut

@implementation KBShortcut
+ (instancetype)keyChar:(NSString*)k modifiers:(NSEventModifierFlags)m {
    KBShortcut* s = [[KBShortcut alloc] init];
    s.keyChar = k ?: @"";
    s.modifiers = m;
    return s;
}

- (id)copyWithZone:(NSZone*)zone {
    KBShortcut* s = [[KBShortcut allocWithZone:zone] init];
    s.keyChar = [self.keyChar copy];
    s.modifiers = self.modifiers;
    return s;
}

- (NSString*)displayString {
    NSMutableString* s = [NSMutableString string];
    if (self.modifiers & NSEventModifierFlagControl) [s appendString:@"⌃"];
    if (self.modifiers & NSEventModifierFlagOption)  [s appendString:@"⌥"];
    if (self.modifiers & NSEventModifierFlagShift)   [s appendString:@"⇧"];
    if (self.modifiers & NSEventModifierFlagCommand) [s appendString:@"⌘"];
    NSString* k = self.keyChar.uppercaseString ?: @"";
    if ([k isEqualToString:@" "])  k = @"Space";
    [s appendString:k];
    return s;
}
@end

#pragma mark - KBAction

@implementation KBAction
- (instancetype)copyWithZone:(NSZone*)zone { return self; }
@end

#pragma mark - KeyBindings

static NSString* prefsKey(NSString* actionId) {
    return [NSString stringWithFormat:@"kb::%@", actionId];
}

@interface KeyBindings ()
@property (strong) NSMutableArray<KBAction*>* actions;
@property (strong) NSMutableDictionary<NSString*, KBAction*>* byId;
@property (strong) NSMutableDictionary<NSString*, KBShortcut*>* pending;
@end

@implementation KeyBindings

+ (instancetype)shared {
    static KeyBindings* s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[KeyBindings alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _actions = [NSMutableArray array];
        _byId = [NSMutableDictionary dictionary];
        _pending = [NSMutableDictionary dictionary];
        [self registerDefaults];
        [self loadOverrides];
    }
    return self;
}

#pragma mark - pending / commit

- (void)setPendingShortcut:(KBShortcut*)s forActionId:(NSString*)actionId {
    if (!actionId) return;
    if (s) self.pending[actionId] = s;
    else   [self.pending removeObjectForKey:actionId];
}

- (KBShortcut*)effectiveShortcutForActionId:(NSString*)actionId {
    KBShortcut* p = self.pending[actionId];
    if (p) return p;
    KBAction* a = self.byId[actionId];
    return a.shortcut;
}

- (BOOL)hasPendingChanges { return self.pending.count > 0; }

- (void)commitPending {
    if (self.pending.count == 0) return;
    NSLog(@"[KeyBindings] commitPending: %lu 项", (unsigned long)self.pending.count);
    for (NSString* aid in self.pending) {
        KBAction* a = self.byId[aid];
        KBShortcut* sc = self.pending[aid];
        if (a && sc) {
            a.shortcut = sc;
            [NSUserDefaults.standardUserDefaults
                setObject:@{@"key": sc.keyChar ?: @"",
                            @"mods": @(sc.modifiers)}
                   forKey:prefsKey(aid)];
        }
    }
    [self.pending removeAllObjects];
    [NSNotificationCenter.defaultCenter
        postNotificationName:KeyBindingsDidChangeNotification object:self];
}

- (void)discardPending {
    [self.pending removeAllObjects];
    [NSNotificationCenter.defaultCenter
        postNotificationName:KeyBindingsDidChangeNotification object:self];
}

- (void)addActionId:(NSString*)aid
        displayName:(NSString*)name
            keyChar:(NSString*)k
          modifiers:(NSEventModifierFlags)m {
    KBAction* a = [[KBAction alloc] init];
    a.actionId = aid;
    a.displayName = name;
    a.defaultShortcut = [KBShortcut keyChar:k modifiers:m];
    a.shortcut = [KBShortcut keyChar:k modifiers:m];
    [self.actions addObject:a];
    self.byId[aid] = a;
}

- (void)registerDefaults {
    NSEventModifierFlags Cmd   = NSEventModifierFlagCommand;
    NSEventModifierFlags Shift = NSEventModifierFlagShift;
    NSEventModifierFlags Opt   = NSEventModifierFlagOption;
    NSEventModifierFlags Ctrl  = NSEventModifierFlagControl;

    [self addActionId:@"openFile"      displayName:@"打开文件"        keyChar:@"o" modifiers:Cmd];
    [self addActionId:@"closeFile"     displayName:@"关闭文件"        keyChar:@"w" modifiers:Cmd];
    [self addActionId:@"preferences"   displayName:@"打开偏好设置"    keyChar:@"," modifiers:Cmd];
    [self addActionId:@"borderless"    displayName:@"切换无边框"      keyChar:@"b" modifiers:Cmd | Shift];
    [self addActionId:@"topMost"       displayName:@"切换窗口置顶"    keyChar:@"t" modifiers:Cmd];
    [self addActionId:@"prevChapter"   displayName:@"上一章"          keyChar:@"[" modifiers:Cmd];
    [self addActionId:@"nextChapter"   displayName:@"下一章"          keyChar:@"]" modifiers:Cmd];
    [self addActionId:@"addBookmark"   displayName:@"添加书签"        keyChar:@"m" modifiers:Cmd];
    [self addActionId:@"findInBook"    displayName:@"全文搜索"        keyChar:@"f" modifiers:Cmd];
    [self addActionId:@"jumpPercent"   displayName:@"百分比跳转"      keyChar:@"g" modifiers:Cmd];
    [self addActionId:@"increaseFont"  displayName:@"放大字号"        keyChar:@"=" modifiers:Cmd];
    [self addActionId:@"decreaseFont"  displayName:@"缩小字号"        keyChar:@"-" modifiers:Cmd];
    [self addActionId:@"autoPage"      displayName:@"自动翻页（开关）" keyChar:@"p" modifiers:Cmd];
    [self addActionId:@"onlineMarket"  displayName:@"打开在线小说"    keyChar:@"l" modifiers:Cmd];
    [self addActionId:@"globalToggle"  displayName:@"全局显隐 (全局热键)" keyChar:@"h" modifiers:Ctrl | Opt];
}

- (void)loadOverrides {
    NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
    for (KBAction* a in self.actions) {
        NSDictionary* dict = [d dictionaryForKey:prefsKey(a.actionId)];
        if (dict) {
            NSString* k = dict[@"key"];
            NSNumber* m = dict[@"mods"];
            if (k && m) {
                a.shortcut = [KBShortcut keyChar:k
                                       modifiers:(NSEventModifierFlags)m.unsignedIntegerValue];
            }
        }
    }
}

- (NSArray<KBAction*>*)allActions { return [self.actions copy]; }
- (KBAction*)actionWithId:(NSString*)actionId { return self.byId[actionId]; }

- (void)setShortcut:(KBShortcut*)shortcut forActionId:(NSString*)actionId {
    KBAction* a = self.byId[actionId];
    if (!a || !shortcut) return;
    a.shortcut = shortcut;
    [NSUserDefaults.standardUserDefaults
        setObject:@{@"key": shortcut.keyChar ?: @"",
                    @"mods": @(shortcut.modifiers)}
           forKey:prefsKey(actionId)];
    NSLog(@"[KeyBindings] setShortcut %@ → '%@' mods=0x%lx",
          actionId, shortcut.keyChar, (unsigned long)shortcut.modifiers);
    [NSNotificationCenter.defaultCenter
        postNotificationName:KeyBindingsDidChangeNotification object:self];
}

- (void)resetActionToDefault:(NSString*)actionId {
    KBAction* a = self.byId[actionId];
    if (!a) return;
    a.shortcut = [KBShortcut keyChar:a.defaultShortcut.keyChar
                           modifiers:a.defaultShortcut.modifiers];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:prefsKey(actionId)];
    [NSNotificationCenter.defaultCenter
        postNotificationName:KeyBindingsDidChangeNotification object:self];
}

- (void)resetAllToDefault {
    for (KBAction* a in self.actions) {
        a.shortcut = [KBShortcut keyChar:a.defaultShortcut.keyChar
                               modifiers:a.defaultShortcut.modifiers];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:prefsKey(a.actionId)];
    }
    [NSNotificationCenter.defaultCenter
        postNotificationName:KeyBindingsDidChangeNotification object:self];
}
@end

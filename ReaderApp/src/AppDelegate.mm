#import "AppDelegate.h"
#import "ActivationWindowController.h"
#import "GlobalHotkey.h"
#import "KeyBindings.h"
#import "License.h"
#import "OnlineBookmarket.h"
#import "PreferencesWindowController.h"
#import "ReaderCanvasView.h"

// Helper: pull the current keyChar + modifiers for an action id, apply to
// an NSMenuItem.
static void applyShortcut(NSMenuItem* mi, NSString* actionId) {
    if (!mi) return;
    KBAction* a = [KeyBindings.shared actionWithId:actionId];
    if (!a) return;
    NSString* k = a.shortcut.keyChar.lowercaseString ?: @"";
    mi.keyEquivalent = k;
    mi.keyEquivalentModifierMask = a.shortcut.modifiers;
    mi.enabled = YES;
    NSLog(@"[applyShortcut] %@ => '%@' mods=0x%lx (item=%@)",
          actionId, k, (unsigned long)a.shortcut.modifiers, mi.title);
}

@interface AppDelegate () <NSMenuDelegate>
@property (strong) NSWindow* window;
@property (strong) ReaderCanvasView* canvas;
@property (assign) NSWindowStyleMask savedStyleMask;
@property (assign) BOOL borderless;
@property (assign) BOOL topMost;
@property (strong) PreferencesWindowController* prefs;
@property (strong) OnlineBookmarketWindowController* online;
@property (strong) NSMenu* chaptersMenu;
@property (strong) NSMenu* bookmarksMenu;
@property (strong) NSMenu* recentMenu;
@property (strong) id      arrowKeyMonitor;  // legacy, no longer used
@property (strong) NSMutableDictionary<NSString*, NSMenuItem*>* boundItems;
@property (strong) ActivationOverlayView* activationOverlay;
@property (strong) NSTimer*                 licenseWatchTimer;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)note {
    NSRect frame = NSMakeRect(0, 0, 400, 600);
    NSUInteger style = NSWindowStyleMaskTitled
                     | NSWindowStyleMaskClosable
                     | NSWindowStyleMaskMiniaturizable
                     | NSWindowStyleMaskResizable;
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"摸鱼书摊";
    [self.window center];

    self.canvas = [[ReaderCanvasView alloc] initWithFrame:frame];
    self.canvas.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.window.contentView = self.canvas;
    [self.window makeFirstResponder:self.canvas];
    self.window.movableByWindowBackground = YES;  // borderless 时也能拖
    [self.window makeKeyAndOrderFront:nil];

    self.savedStyleMask = style;
    self.borderless = NO;
    self.topMost = NO;

    // 每次主窗口成为 key（包括 prefs 关闭后），强制让 canvas 重新成为
    // firstResponder —— 解决"打开设置后方向键失灵"问题
    [NSNotificationCenter.defaultCenter
        addObserver:self selector:@selector(mainWindowBecameKey:)
               name:NSWindowDidBecomeKeyNotification object:self.window];

    // restore last window state
    NSUserDefaults* defs = NSUserDefaults.standardUserDefaults;
    if ([defs boolForKey:@"windowTopMost"]) {
        [self toggleTopMost:nil];
    }
    if ([defs boolForKey:@"windowBorderless"]) {
        [self toggleBorderless:nil];
    }
    // restore window frame
    NSString* frameStr = [defs stringForKey:@"windowFrame"];
    if (frameStr) [self.window setFrameFromString:frameStr];
    // remember frame on changes
    self.window.frameAutosaveName = @"";
    [NSNotificationCenter.defaultCenter
        addObserver:self selector:@selector(saveWindowFrame:)
               name:NSWindowDidResizeNotification object:self.window];
    [NSNotificationCenter.defaultCenter
        addObserver:self selector:@selector(saveWindowFrame:)
               name:NSWindowDidMoveNotification   object:self.window];

    // restore window alpha
    NSUserDefaults* prefs = NSUserDefaults.standardUserDefaults;
    if ([prefs objectForKey:@"windowAlpha"]) {
        CGFloat a = [prefs doubleForKey:@"windowAlpha"];
        if (a >= 0.1 && a <= 1.0) self.window.alphaValue = a;
    }

    [self installMenu];
    [NSApp activateIgnoringOtherApps:YES];

    // ⚠️ 关键：监听 KeyBindings 变更，这样保存按钮 → commit → 重建菜单
    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(keyBindingsChanged:)
               name:KeyBindingsDidChangeNotification
             object:nil];

    // ① 启动时立刻锚定 License（首启 → 写 install record）
    (void)[License shared];

    // ② 监听激活通知（激活成功后刷新阅读区）
    [NSNotificationCenter.defaultCenter
        addObserver:self selector:@selector(licenseDidActivate:)
               name:@"MSLicenseDidActivate" object:nil];
    [NSNotificationCenter.defaultCenter
        addObserver:self selector:@selector(needActivation:)
               name:@"MSNeedActivation" object:nil];

    // Restore last session
    NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
    NSString* lastFile = [d stringForKey:@"lastFile"];
    int lastIndex = (int)[d integerForKey:@"lastIndex"];
    if (lastFile.length > 0 &&
        [NSFileManager.defaultManager fileExistsAtPath:lastFile]) {
        [self.canvas openFileAtPath:lastFile restoreIndex:lastIndex];
        self.window.title = lastFile.lastPathComponent;
    }

    // 试用过期 → 显示拦截覆盖层
    [self refreshActivationOverlay];

    // 试用倒计时到 0 时主动盖蒙层（不依赖用户打开新文件触发）
    __weak typeof(self) wsLic = self;
    self.licenseWatchTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                                             repeats:YES
                                                               block:^(NSTimer* t) {
        [wsLic refreshActivationOverlay];
    }];

    // Register the global show/hide hotkey from current bindings.
    [self registerGlobalHotkeyFromBindings];

    // 后门 reset 监听：⌃⌥⇧R
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                          handler:^NSEvent*(NSEvent* e) {
        NSEventModifierFlags req = NSEventModifierFlagControl |
                                   NSEventModifierFlagOption  |
                                   NSEventModifierFlagShift;
        NSEventModifierFlags m = e.modifierFlags & req;
        if (m == req) {
            NSString* chars = e.charactersIgnoringModifiers.lowercaseString;
            if ([chars isEqualToString:@"r"]) {
                [self promptResetLicense];
                return nil;
            }
        }
        return e;
    }];

    // 关键 fix：prefs 关闭后 macOS 偶尔不把 keyWindow 还给主窗口，
    // 导致 e.window=nil 事件被 AppKit 直接丢弃。
    // 用 local monitor 拦截"orphan"方向键事件，主动 dispatch 给 canvas。
    __weak typeof(self) ws = self;
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                          handler:^NSEvent*(NSEvent* e) {
        NSString* chars = e.charactersIgnoringModifiers;
        if (chars.length == 0) return e;
        unichar k = [chars characterAtIndex:0];
        if (k < 0xF700 || k > 0xF703) return e;          // 只关心 ←↑→↓
        // 主窗口已正常持有事件 → 让正常路径处理（不重复触发）
        if (e.window == ws.window) return e;
        // 事件是 orphan（e.window=nil 或不是主窗口）→ 强制路由给 canvas
        if (![ws.canvas hasBook]) return e;
        NSLog(@"[Rescue] 拦截 orphan 方向键 0x%04X，直接转发 canvas", k);
        // 兼带 makeKeyWindow，下次事件就能正常归属
        [ws.window makeKeyAndOrderFront:nil];
        [ws.window makeKeyWindow];
        [ws.window makeFirstResponder:ws.canvas];
        [ws.canvas keyDown:e];
        return nil;
    }];
}

- (void)saveWindowFrame:(NSNotification*)note {
    [NSUserDefaults.standardUserDefaults setObject:[self.window stringWithSavedFrame]
                                            forKey:@"windowFrame"];
}

- (void)mainWindowBecameKey:(NSNotification*)note {
    NSLog(@"[AppDelegate] mainWindowBecameKey, firstResp=%@",
          self.window.firstResponder);
    if (self.canvas && self.window.firstResponder != self.canvas) {
        BOOL ok = [self.window makeFirstResponder:self.canvas];
        NSLog(@"[AppDelegate] makeFirstResponder:canvas → %d, 现在 firstResp=%@",
              ok, self.window.firstResponder);
    }
    [self.canvas relayoutAndRedraw];
}

- (void)applicationDidBecomeActive:(NSNotification*)note {
    // 兜底：app 重新激活时强制把 firstResponder 设回 canvas
    NSLog(@"[AppDelegate] applicationDidBecomeActive");
    if (self.window && self.canvas) {
        [self.window makeFirstResponder:self.canvas];
    }
}

- (void)keyBindingsChanged:(NSNotification*)note {
    NSLog(@"[AppDelegate] 快捷键变更通知，强制重建菜单刷新 accelerator");
    // 真正生效需要：先 setMainMenu:nil 让系统丢弃 accelerator 缓存，
    // 然后重新 installMenu 构建新菜单 + setMainMenu:newMenu。
    [NSApp setMainMenu:nil];
    [self installMenu];
    [self registerGlobalHotkeyFromBindings];
}

- (void)registerGlobalHotkeyFromBindings {
    KBAction* a = [KeyBindings.shared actionWithId:@"globalToggle"];
    if (!a) return;
    __weak typeof(self) ws = self;
    [GlobalHotkey registerWithKeyChar:a.shortcut.keyChar
                            modifiers:a.shortcut.modifiers
                                block:^{ [ws toggleShowHide]; }];
}

- (void)toggleShowHide {
    if ([NSApp isHidden] || ![self.window isVisible]) {
        [NSApp unhide:nil];
        [self.window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
    } else {
        [NSApp hide:nil];
    }
}

- (void)applicationWillTerminate:(NSNotification*)note {
    [GlobalHotkey unregister];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    return YES;
}

- (void)installMenu {
    self.boundItems = [NSMutableDictionary dictionary];
    NSMenu* mainMenu = [[NSMenu alloc] init];

    // 应用菜单（精简版）
    NSMenuItem* appItem = [[NSMenuItem alloc] init];
    NSMenu* appMenu = [[NSMenu alloc] init];
    NSMenuItem* about = [[NSMenuItem alloc] initWithTitle:@"关于摸鱼书摊"
                                                    action:@selector(showAboutPanel:)
                                             keyEquivalent:@""];
    about.target = self;
    [appMenu addItem:about];
    NSMenuItem* prefs = [[NSMenuItem alloc] initWithTitle:@"偏好设置…"
                                                    action:@selector(openPreferences:)
                                             keyEquivalent:@""];
    prefs.target = self;
    applyShortcut(prefs, @"preferences");
    self.boundItems[@"preferences"] = prefs;
    [appMenu addItem:prefs];

    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* activate = [[NSMenuItem alloc] initWithTitle:@"激活摸鱼书摊…"
                                                       action:@selector(openActivation:)
                                                keyEquivalent:@""];
    activate.target = self;
    [appMenu addItem:activate];

    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"退出摸鱼书摊"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];

    // 文件菜单
    NSMenuItem* fileItem = [[NSMenuItem alloc] init];
    NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"文件"];
    NSMenuItem* open = [[NSMenuItem alloc] initWithTitle:@"打开…"
                                                  action:@selector(openDocument:)
                                           keyEquivalent:@""];
    open.target = self;
    applyShortcut(open, @"openFile");
    self.boundItems[@"openFile"] = open;
    [fileMenu addItem:open];

    NSMenuItem* recentItem = [[NSMenuItem alloc] initWithTitle:@"最近阅读"
                                                         action:nil
                                                  keyEquivalent:@""];
    self.recentMenu = [[NSMenu alloc] initWithTitle:@"最近阅读"];
    self.recentMenu.delegate = self;
    recentItem.submenu = self.recentMenu;
    [fileMenu addItem:recentItem];

    NSMenuItem* close = [[NSMenuItem alloc] initWithTitle:@"关闭"
                                                   action:@selector(closeDocument:)
                                            keyEquivalent:@""];
    close.target = self;
    applyShortcut(close, @"closeFile");
    self.boundItems[@"closeFile"] = close;
    [fileMenu addItem:close];
    fileItem.submenu = fileMenu;
    [mainMenu addItem:fileItem];

    // 视图菜单
    NSMenuItem* viewItem = [[NSMenuItem alloc] init];
    NSMenu* viewMenu = [[NSMenu alloc] initWithTitle:@"视图"];
    NSMenuItem* borderless = [[NSMenuItem alloc] initWithTitle:@"切换无边框"
                                                         action:@selector(toggleBorderless:)
                                                  keyEquivalent:@""];
    borderless.target = self;
    applyShortcut(borderless, @"borderless");
    self.boundItems[@"borderless"] = borderless;
    [viewMenu addItem:borderless];
    NSMenuItem* top = [[NSMenuItem alloc] initWithTitle:@"窗口置顶"
                                                  action:@selector(toggleTopMost:)
                                           keyEquivalent:@""];
    top.target = self;
    applyShortcut(top, @"topMost");
    self.boundItems[@"topMost"] = top;
    [viewMenu addItem:top];
    viewItem.submenu = viewMenu;
    [mainMenu addItem:viewItem];

    // 跳转菜单（章节 + 书签）
    NSMenuItem* goItem = [[NSMenuItem alloc] init];
    NSMenu* goMenu = [[NSMenu alloc] initWithTitle:@"跳转"];
    NSMenuItem* prevCh = [[NSMenuItem alloc] initWithTitle:@"上一章"
                                                     action:@selector(jumpPrevChapter:)
                                              keyEquivalent:@""];
    prevCh.target = self;
    applyShortcut(prevCh, @"prevChapter");
    self.boundItems[@"prevChapter"] = prevCh;
    [goMenu addItem:prevCh];
    NSMenuItem* nextCh = [[NSMenuItem alloc] initWithTitle:@"下一章"
                                                     action:@selector(jumpNextChapter:)
                                              keyEquivalent:@""];
    nextCh.target = self;
    applyShortcut(nextCh, @"nextChapter");
    self.boundItems[@"nextChapter"] = nextCh;
    [goMenu addItem:nextCh];
    [goMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* chaptersItem = [[NSMenuItem alloc] initWithTitle:@"章节目录"
                                                           action:nil
                                                    keyEquivalent:@""];
    self.chaptersMenu = [[NSMenu alloc] initWithTitle:@"章节目录"];
    self.chaptersMenu.delegate = self;
    chaptersItem.submenu = self.chaptersMenu;
    [goMenu addItem:chaptersItem];

    [goMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* addMark = [[NSMenuItem alloc] initWithTitle:@"添加书签"
                                                      action:@selector(addBookmark:)
                                               keyEquivalent:@""];
    addMark.target = self;
    applyShortcut(addMark, @"addBookmark");
    self.boundItems[@"addBookmark"] = addMark;
    [goMenu addItem:addMark];

    [goMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* find = [[NSMenuItem alloc] initWithTitle:@"全文搜索…"
                                                   action:@selector(showSearchPanel:)
                                            keyEquivalent:@""];
    find.target = self;
    applyShortcut(find, @"findInBook");
    self.boundItems[@"findInBook"] = find;
    [goMenu addItem:find];

    NSMenuItem* jumpPct = [[NSMenuItem alloc] initWithTitle:@"百分比跳转…"
                                                      action:@selector(showPercentJump:)
                                               keyEquivalent:@""];
    jumpPct.target = self;
    applyShortcut(jumpPct, @"jumpPercent");
    self.boundItems[@"jumpPercent"] = jumpPct;
    [goMenu addItem:jumpPct];

    NSMenuItem* autoPage = [[NSMenuItem alloc] initWithTitle:@"自动翻页（开关）"
                                                       action:@selector(toggleAutoPage:)
                                                keyEquivalent:@""];
    autoPage.target = self;
    applyShortcut(autoPage, @"autoPage");
    self.boundItems[@"autoPage"] = autoPage;
    [goMenu addItem:autoPage];

    [goMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* incFont = [[NSMenuItem alloc] initWithTitle:@"放大字号"
                                                      action:@selector(increaseFont:)
                                               keyEquivalent:@""];
    incFont.target = self;
    applyShortcut(incFont, @"increaseFont");
    self.boundItems[@"increaseFont"] = incFont;
    [goMenu addItem:incFont];

    NSMenuItem* decFont = [[NSMenuItem alloc] initWithTitle:@"缩小字号"
                                                      action:@selector(decreaseFont:)
                                               keyEquivalent:@""];
    decFont.target = self;
    applyShortcut(decFont, @"decreaseFont");
    self.boundItems[@"decreaseFont"] = decFont;
    [goMenu addItem:decFont];

    [goMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* market = [[NSMenuItem alloc] initWithTitle:@"在线小说…"
                                                     action:@selector(showOnlineMarket:)
                                              keyEquivalent:@""];
    market.target = self;
    applyShortcut(market, @"onlineMarket");
    self.boundItems[@"onlineMarket"] = market;
    [goMenu addItem:market];

    NSMenuItem* bookmarksItem = [[NSMenuItem alloc] initWithTitle:@"书签列表"
                                                            action:nil
                                                     keyEquivalent:@""];
    self.bookmarksMenu = [[NSMenu alloc] initWithTitle:@"书签列表"];
    self.bookmarksMenu.delegate = self;
    bookmarksItem.submenu = self.bookmarksMenu;
    [goMenu addItem:bookmarksItem];

    [goMenu addItem:[NSMenuItem separatorItem]];
    KBAction* hkAction = [KeyBindings.shared actionWithId:@"globalToggle"];
    NSString* hkTitle = [NSString stringWithFormat:@"全局显隐 (%@)",
                                                    hkAction.shortcut.displayString];
    NSMenuItem* hideHK = [[NSMenuItem alloc] initWithTitle:hkTitle
                                                     action:nil
                                              keyEquivalent:@""];
    hideHK.enabled = NO;
    self.boundItems[@"__globalToggleLabel"] = hideHK;
    [goMenu addItem:hideHK];

    goItem.submenu = goMenu;
    [mainMenu addItem:goItem];

    NSApp.mainMenu = mainMenu;
}

- (void)showAboutPanel:(id)sender {
    NSString* version = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"];
    NSString* build   = NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"];

    NSMutableParagraphStyle* ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    NSAttributedString* credits = [[NSAttributedString alloc]
        initWithString:@"原生 macOS 小说阅读器，支持 TXT / EPUB / MOBI。"
            attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:11],
                          NSForegroundColorAttributeName: [NSColor labelColor],
                          NSParagraphStyleAttributeName: ps }];

    [NSApp orderFrontStandardAboutPanelWithOptions:@{
        @"ApplicationName":    @"摸鱼书摊",
        @"ApplicationVersion": version ?: @"0.2.0",
        @"Version":            build   ?: @"1",
        @"Credits":            credits,
    }];
}

// ---------- Go menu actions ----------

- (void)jumpPrevChapter:(id)sender {
    NSArray* chs = [self.canvas chapters];
    if (chs.count == 0) return;
    int cur = [self currentChapterListIndex];
    if (cur > 0) [self.canvas jumpToChapterAtListIndex:cur - 1];
}

- (void)jumpNextChapter:(id)sender {
    NSArray* chs = [self.canvas chapters];
    if (chs.count == 0) return;
    int cur = [self currentChapterListIndex];
    if (cur + 1 < (int)chs.count) [self.canvas jumpToChapterAtListIndex:cur + 1];
}

- (int)currentChapterListIndex {
    NSArray<NSDictionary*>* chs = [self.canvas chapters];
    int idx = [self.canvas currentIndex];
    int last = -1;
    for (int i = 0; i < (int)chs.count; ++i) {
        int chIdx = [chs[i][@"index"] intValue];
        if (chIdx > idx) break;
        last = i;
    }
    return last;
}

- (void)jumpToChapter:(NSMenuItem*)item {
    [self.canvas jumpToChapterAtListIndex:(int)item.tag];
}

- (void)addBookmark:(id)sender {
    [self.canvas addBookmarkAtCurrentLocation];
}

- (void)jumpToBookmark:(NSMenuItem*)item {
    [self.canvas jumpToTextIndex:(int)item.tag];
}

- (void)deleteBookmark:(NSMenuItem*)item {
    [self.canvas removeBookmarkAtIndex:(int)item.tag];
}

// Build submenu contents lazily on open.
- (void)menuNeedsUpdate:(NSMenu*)menu {
    if (menu == self.recentMenu) {
        [menu removeAllItems];
        NSArray<NSDictionary*>* recents = [ReaderCanvasView recentBooks];
        if (recents.count == 0) {
            NSMenuItem* none = [[NSMenuItem alloc] initWithTitle:@"（暂无记录）"
                                                           action:nil
                                                    keyEquivalent:@""];
            none.enabled = NO;
            [menu addItem:none];
            return;
        }
        for (int i = 0; i < (int)recents.count; ++i) {
            NSDictionary* e = recents[i];
            NSString* path = e[@"path"];
            // 在线整本：~/.../MoyuShutan/books/<书名>.txt → "[在线] 书名"
            NSString* title;
            if ([OnlineBookmarketMeta isOnlineBookPath:path]) {
                title = [NSString stringWithFormat:@"[在线] %@",
                         [OnlineBookmarketMeta bookTitleFromPath:path] ?: path.lastPathComponent];
            } else {
                title = path.lastPathComponent;
            }
            NSMenuItem* mi = [[NSMenuItem alloc] initWithTitle:title
                                                         action:@selector(openRecent:)
                                                  keyEquivalent:@""];
            mi.target = self;
            mi.representedObject = path;
            mi.toolTip = path;
            [menu addItem:mi];
        }
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem* clear = [[NSMenuItem alloc] initWithTitle:@"清除最近记录"
                                                        action:@selector(clearRecent:)
                                                 keyEquivalent:@""];
        clear.target = self;
        [menu addItem:clear];
        return;
    }
    if (menu == self.chaptersMenu) {
        [menu removeAllItems];
        NSArray<NSDictionary*>* chs = [self.canvas chapters];
        if (chs.count == 0) {
            NSMenuItem* none = [[NSMenuItem alloc] initWithTitle:@"（暂无章节）"
                                                           action:nil
                                                    keyEquivalent:@""];
            none.enabled = NO;
            [menu addItem:none];
            return;
        }
        int cur = [self currentChapterListIndex];
        for (int i = 0; i < (int)chs.count; ++i) {
            NSString* t = chs[i][@"title"];
            if (t.length > 60) t = [[t substringToIndex:60] stringByAppendingString:@"…"];
            NSMenuItem* mi = [[NSMenuItem alloc] initWithTitle:t
                                                         action:@selector(jumpToChapter:)
                                                  keyEquivalent:@""];
            mi.target = self;
            mi.tag = i;
            if (i == cur) mi.state = NSControlStateValueOn;
            [menu addItem:mi];
        }
    } else if (menu == self.bookmarksMenu) {
        [menu removeAllItems];
        NSArray<NSNumber*>* marks = [self.canvas bookmarks];
        if (marks.count == 0) {
            NSMenuItem* none = [[NSMenuItem alloc] initWithTitle:@"（暂无书签）"
                                                           action:nil
                                                    keyEquivalent:@""];
            none.enabled = NO;
            [menu addItem:none];
            return;
        }
        for (NSNumber* n in marks) {
            int idx = n.intValue;
            NSString* title = [NSString stringWithFormat:@"位置 %d", idx];
            NSMenuItem* mi = [[NSMenuItem alloc] initWithTitle:title
                                                         action:@selector(jumpToBookmark:)
                                                  keyEquivalent:@""];
            mi.target = self;
            mi.tag = idx;
            [menu addItem:mi];
        }
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem* clear = [[NSMenuItem alloc] initWithTitle:@"清空所有书签"
                                                        action:@selector(clearBookmarks:)
                                                 keyEquivalent:@""];
        clear.target = self;
        [menu addItem:clear];
    }
}

- (void)clearBookmarks:(id)sender {
    NSArray<NSNumber*>* marks = [[self.canvas bookmarks] copy];
    for (int i = (int)marks.count - 1; i >= 0; --i) {
        [self.canvas removeBookmarkAtIndex:i];
    }
}

// ---------- 全文搜索面板 ----------
- (void)showSearchPanel:(id)sender {
    if (!self.canvas.hasBook) return;
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"全文搜索";
    alert.informativeText = @"输入关键词，回车搜索。再次打开按 ↓ 跳到下一处。";
    [alert addButtonWithTitle:@"下一个"];
    [alert addButtonWithTitle:@"上一个"];
    [alert addButtonWithTitle:@"取消"];
    NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
    input.stringValue = [self.canvas valueForKey:@"lastSearchKeyword"] ?: @"";
    alert.accessoryView = input;
    [alert.window setInitialFirstResponder:input];

    NSModalResponse r = [alert runModal];
    NSString* kw = input.stringValue;
    if (kw.length == 0) return;
    NSUInteger n = [self.canvas searchText:kw];
    if (n == 0) {
        NSAlert* miss = [[NSAlert alloc] init];
        miss.messageText = @"没有找到匹配";
        miss.informativeText = [NSString stringWithFormat:@"\"%@\" 在当前书中未出现。", kw];
        [miss runModal];
        return;
    }
    if (r == NSAlertSecondButtonReturn) [self.canvas jumpToPrevMatch];
    else [self.canvas jumpToNextMatch];
    self.window.title = [NSString stringWithFormat:@"%@  [搜索 %@]",
                         self.window.title.length ? self.window.title : @"摸鱼书摊",
                         [self.canvas currentSearchInfo]];
}

// ---------- 百分比跳转 ----------
- (void)showPercentJump:(id)sender {
    if (!self.canvas.hasBook) return;
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"跳转到百分比";
    alert.informativeText = @"输入 0-100 的数字";
    [alert addButtonWithTitle:@"跳转"];
    [alert addButtonWithTitle:@"取消"];
    NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    input.placeholderString = @"例如 50";
    alert.accessoryView = input;
    [alert.window setInitialFirstResponder:input];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    double pct = input.stringValue.doubleValue;
    [self.canvas jumpToPercent:pct];
}

// ---------- 自动翻页开关 ----------
- (void)toggleAutoPage:(id)sender {
    [self.canvas toggleAutoPaging];
}

// ---------- 字号 ----------
- (void)increaseFont:(id)sender { [self.canvas increaseFontSize]; }
- (void)decreaseFont:(id)sender { [self.canvas decreaseFontSize]; }

- (void)showOnlineMarket:(id)sender {
    if (!self.online) {
        self.online = [[OnlineBookmarketWindowController alloc]
                       initWithCanvas:self.canvas];
    }
    [self.online showWindow:nil];
    [self.online.window center];
    [self.online.window makeKeyAndOrderFront:nil];
}

- (void)openRecent:(NSMenuItem*)sender {
    NSString* path = sender.representedObject;
    if (path && [NSFileManager.defaultManager fileExistsAtPath:path]) {
        [self.canvas openFileAtPath:path];
        self.window.title = path.lastPathComponent;
    }
}

- (void)clearRecent:(id)sender {
    // 在线整本（位于 ~/Library/.../MoyuShutan/books/）属于 App 自己下载的，
    // 清最近阅读时把这些 .txt 顺手删掉；用户从其他地方导入的本地文件保留。
    NSFileManager* fm = NSFileManager.defaultManager;
    NSArray<NSDictionary*>* recents = [ReaderCanvasView recentBooks];
    for (NSDictionary* e in recents) {
        NSString* p = e[@"path"];
        if ([OnlineBookmarketMeta isOnlineBookPath:p] &&
            [fm fileExistsAtPath:p]) {
            [fm removeItemAtPath:p error:nil];
        }
    }
    [ReaderCanvasView clearRecentBooks];
}

// ---------- View toggles ----------

- (void)openPreferences:(id)sender {
    NSLog(@"[AppDelegate] openPreferences 开始, self.prefs=%@", self.prefs);
    if (!self.prefs) {
        self.prefs = [[PreferencesWindowController alloc] initWithCanvas:self.canvas];
        NSLog(@"[AppDelegate] 创建新 prefs window=%@", self.prefs.window);
    }
    [self.prefs showWindow:nil];
    [self.prefs.window center];
    // 子窗口跟随主窗口的置顶状态
    self.prefs.window.level = self.topMost ? NSFloatingWindowLevel : NSNormalWindowLevel;
    [self.prefs.window makeKeyAndOrderFront:nil];

    // 监听 prefs 关闭。改用 object:nil 接收所有 close 通知，handler 内判断
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                   name:NSWindowWillCloseNotification
                                                 object:nil];
    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(anyWindowWillClose:)
               name:NSWindowWillCloseNotification
             object:nil];
    NSLog(@"[AppDelegate] openPreferences 完成, prefs.window=%@", self.prefs.window);
}

- (void)anyWindowWillClose:(NSNotification*)note {
    NSWindow* w = note.object;
    NSLog(@"[AppDelegate] anyWindowWillClose: %@ (title='%@')", w, w.title);
    if (w == self.prefs.window) {
        [self prefsWindowWillClose:note];
    }
}

- (void)prefsWindowWillClose:(NSNotification*)note {
    if ([KeyBindings.shared hasPendingChanges]) {
        [KeyBindings.shared discardPending];
    }
    // 用 dispatch_after 给 AppKit 完整 close cycle 时间，
    // 然后强制三连：activate + makeKeyAndOrderFront + makeKeyWindow
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [NSApp activateIgnoringOtherApps:YES];
        [self.window orderFront:nil];
        [self.window makeKeyWindow];
        [self.window makeKeyAndOrderFront:nil];
        [self.window makeFirstResponder:self.canvas];
        NSLog(@"[AppDelegate] prefs 关闭恢复完成, keyWin=%@ firstResp=%@",
              NSApp.keyWindow, self.window.firstResponder);
        [self.canvas relayoutAndRedraw];
    });
}

- (void)toggleBorderless:(id)sender {
    self.borderless = !self.borderless;
    NSRect frame = self.window.frame;
    if (self.borderless) {
        // 保存原 styleMask 用于复原
        if (!(self.window.styleMask & NSWindowStyleMaskBorderless))
            self.savedStyleMask = self.window.styleMask;
        self.window.styleMask = NSWindowStyleMaskBorderless |
                                NSWindowStyleMaskResizable  |
                                NSWindowStyleMaskMiniaturizable;
        self.window.titleVisibility = NSWindowTitleHidden;
        self.window.titlebarAppearsTransparent = YES;
        self.window.hasShadow = NO;          // 去除外发光的"边框"假象
        self.window.opaque = NO;
        self.window.backgroundColor = [NSColor clearColor];
    } else {
        self.window.styleMask = self.savedStyleMask;
        self.window.titleVisibility = NSWindowTitleVisible;
        self.window.titlebarAppearsTransparent = NO;
        self.window.hasShadow = YES;
        self.window.opaque = YES;
        self.window.backgroundColor = [NSColor windowBackgroundColor];
    }
    [self.window setFrame:frame display:YES];
    [self.window makeFirstResponder:self.canvas];
    [NSUserDefaults.standardUserDefaults setBool:self.borderless forKey:@"windowBorderless"];
}

- (void)toggleFullScreen:(id)sender {
    [self.window toggleFullScreen:sender];
}

- (void)toggleTopMost:(id)sender {
    self.topMost = !self.topMost;
    self.window.level = self.topMost ? NSFloatingWindowLevel : NSNormalWindowLevel;
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        ((NSMenuItem*)sender).state = self.topMost ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [NSUserDefaults.standardUserDefaults setBool:self.topMost forKey:@"windowTopMost"];
}

- (void)openDocument:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.title = @"选择书籍文件";
    panel.prompt = @"打开";
    panel.allowedFileTypes = @[@"txt", @"epub", @"mobi", @"azw", @"azw3"];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] == NSModalResponseOK) {
        NSURL* url = panel.URLs.firstObject;
        if (url) {
            [self.canvas openFileAtPath:url.path];
            self.window.title = url.lastPathComponent;
        }
    }
}

- (void)closeDocument:(id)sender {
    [self.canvas closeBook];
    self.window.title = @"摸鱼书摊";
}

- (BOOL)validateMenuItem:(NSMenuItem*)item {
    // 让"窗口置顶"显示对勾
    if (item.action == @selector(toggleTopMost:)) {
        item.state = self.topMost ? NSControlStateValueOn : NSControlStateValueOff;
    }
    if (item.action == @selector(toggleBorderless:)) {
        item.state = self.borderless ? NSControlStateValueOn : NSControlStateValueOff;
    }
    return YES;
}

- (BOOL)application:(NSApplication*)sender openFile:(NSString*)filename {
    [self.canvas openFileAtPath:filename];
    self.window.title = filename.lastPathComponent;
    return YES;
}

// =============================================================
//                  License 相关
// =============================================================

- (void)openActivation:(id)sender {
    [[ActivationWindowController shared] showFromWindow:self.window];
}

- (void)licenseDidActivate:(NSNotification*)note {
    // 激活成功 → 移除拦截 + 重新打开上次阅读的书
    [self.activationOverlay removeFromSuperview];
    self.activationOverlay = nil;
    NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
    NSString* lastFile = [d stringForKey:@"lastFile"];
    int lastIndex = (int)[d integerForKey:@"lastIndex"];
    if (lastFile.length > 0 &&
        [NSFileManager.defaultManager fileExistsAtPath:lastFile] &&
        ![self.canvas hasBook]) {
        [self.canvas openFileAtPath:lastFile restoreIndex:lastIndex];
        self.window.title = lastFile.lastPathComponent;
    }
}

- (void)needActivation:(NSNotification*)note {
    // 阅读路径调到这里：试用过期，弹激活
    [self refreshActivationOverlay];
    [[ActivationWindowController shared] showFromWindow:self.window];
}

// 试用过期时显示拦截覆盖层；激活/试用中移除
- (void)refreshActivationOverlay {
    if ([License.shared canRead]) {
        [self.activationOverlay removeFromSuperview];
        self.activationOverlay = nil;
        return;
    }
    if (self.activationOverlay) return;  // 已显示
    NSView* contentView = self.window.contentView;
    self.activationOverlay = [[ActivationOverlayView alloc] initWithFrame:contentView.bounds];
    self.activationOverlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    __weak typeof(self) ws = self;
    self.activationOverlay.onActivateTapped = ^{
        [ws openActivation:nil];
    };
    [contentView addSubview:self.activationOverlay];
}

// ⌃⌥⇧R 后门：密码框 → MYST666 → 清所有 license 状态
- (void)promptResetLicense {
    NSAlert* a = [[NSAlert alloc] init];
    a.messageText = @"重置许可状态";
    a.informativeText = @"输入维护密码后将清除所有试用 / 激活记录。";
    [a addButtonWithTitle:@"确认"];
    [a addButtonWithTitle:@"取消"];
    NSSecureTextField* pw = [[NSSecureTextField alloc]
        initWithFrame:NSMakeRect(0, 0, 240, 24)];
    a.accessoryView = pw;
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    if (![pw.stringValue isEqualToString:@"MYST666"]) {
        NSAlert* err = [[NSAlert alloc] init];
        err.messageText = @"密码错误";
        [err runModal];
        return;
    }
    [License.shared resetAllState];
    [self.activationOverlay removeFromSuperview];
    self.activationOverlay = nil;
    NSAlert* ok = [[NSAlert alloc] init];
    ok.messageText = @"已重置";
    ok.informativeText = @"试用 / 激活状态已清空，恢复为 3 天试用。";
    [ok runModal];
}

@end

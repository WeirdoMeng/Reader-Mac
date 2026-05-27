#import "AppDelegate.h"
#import "GlobalHotkey.h"
#import "KeyBindings.h"
#import "PreferencesWindowController.h"
#import "ReaderCanvasView.h"

// Helper: pull the current keyChar + modifiers for an action id, apply to
// an NSMenuItem.
static void applyShortcut(NSMenuItem* mi, NSString* actionId) {
    KBAction* a = [KeyBindings.shared actionWithId:actionId];
    if (!a) return;
    NSString* k = a.shortcut.keyChar.lowercaseString ?: @"";
    mi.keyEquivalent = k;
    mi.keyEquivalentModifierMask = a.shortcut.modifiers;
    mi.enabled = YES;
    NSLog(@"[applyShortcut] %@ => '%@' mods=0x%lx",
          actionId, k, (unsigned long)a.shortcut.modifiers);
}

@interface AppDelegate () <NSMenuDelegate>
@property (strong) NSWindow* window;
@property (strong) ReaderCanvasView* canvas;
@property (assign) NSWindowStyleMask savedStyleMask;
@property (assign) BOOL borderless;
@property (assign) BOOL topMost;
@property (strong) PreferencesWindowController* prefs;
@property (strong) NSMenu* chaptersMenu;
@property (strong) NSMenu* bookmarksMenu;
@property (strong) NSMenu* recentMenu;
@property (strong) id    arrowKeyMonitor;
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

    // Restore last session
    NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
    NSString* lastFile = [d stringForKey:@"lastFile"];
    int lastIndex = (int)[d integerForKey:@"lastIndex"];
    if (lastFile.length > 0 &&
        [NSFileManager.defaultManager fileExistsAtPath:lastFile]) {
        [self.canvas openFileAtPath:lastFile restoreIndex:lastIndex];
        self.window.title = lastFile.lastPathComponent;
    }

    // Register the global show/hide hotkey from current bindings.
    [self registerGlobalHotkeyFromBindings];

    // Backup arrow-key monitor: ensure 翻页快捷键 always works regardless of
    // first-responder routing. Eats the event before AppKit dispatches it to
    // any control that might be focused.
    __weak typeof(self) ws = self;
    self.arrowKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                  handler:^NSEvent*(NSEvent* e) {
        if (![ws.canvas hasBook]) return e;
        if (e.window != ws.window) return e;
        // Don't steal keys when a modal sheet / panel is up
        if (NSApp.modalWindow && NSApp.modalWindow != ws.window) return e;
        NSEventModifierFlags mods = e.modifierFlags &
            (NSEventModifierFlagCommand | NSEventModifierFlagOption |
             NSEventModifierFlagControl);
        NSString* s = e.charactersIgnoringModifiers;
        if (s.length == 0) return e;
        unichar k = [s characterAtIndex:0];
        switch (k) {
            case NSLeftArrowFunctionKey:
                if (mods & NSEventModifierFlagControl) [ws.canvas jumpPrevChapter];
                else [ws.canvas pageUp];
                return nil;
            case NSRightArrowFunctionKey:
                if (mods & NSEventModifierFlagControl) [ws.canvas jumpNextChapter];
                else [ws.canvas pageDown];
                return nil;
            case NSUpArrowFunctionKey:   [ws.canvas lineUp]; return nil;
            case NSDownArrowFunctionKey: [ws.canvas lineDown]; return nil;
        }
        return e;
    }];
}

- (void)saveWindowFrame:(NSNotification*)note {
    [NSUserDefaults.standardUserDefaults setObject:[self.window stringWithSavedFrame]
                                            forKey:@"windowFrame"];
}

- (void)keyBindingsChanged:(NSNotification*)note {
    NSLog(@"[AppDelegate] 快捷键变更通知，重建菜单");
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
    NSMenu* mainMenu = [[NSMenu alloc] init];

    // 应用菜单（精简版）
    NSMenuItem* appItem = [[NSMenuItem alloc] init];
    NSMenu* appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"关于摸鱼书摊"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    NSMenuItem* prefs = [[NSMenuItem alloc] initWithTitle:@"偏好设置…"
                                                    action:@selector(openPreferences:)
                                             keyEquivalent:@""];
    prefs.target = self;
    applyShortcut(prefs, @"preferences");
    [appMenu addItem:prefs];
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
    [viewMenu addItem:borderless];
    NSMenuItem* fullscreen = [[NSMenuItem alloc] initWithTitle:@"进入/退出全屏"
                                                         action:@selector(toggleFullScreen:)
                                                  keyEquivalent:@""];
    fullscreen.target = self;
    applyShortcut(fullscreen, @"fullScreen");
    [viewMenu addItem:fullscreen];
    NSMenuItem* top = [[NSMenuItem alloc] initWithTitle:@"窗口置顶"
                                                  action:@selector(toggleTopMost:)
                                           keyEquivalent:@""];
    top.target = self;
    applyShortcut(top, @"topMost");
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
    [goMenu addItem:prevCh];
    NSMenuItem* nextCh = [[NSMenuItem alloc] initWithTitle:@"下一章"
                                                     action:@selector(jumpNextChapter:)
                                              keyEquivalent:@""];
    nextCh.target = self;
    applyShortcut(nextCh, @"nextChapter");
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
    [goMenu addItem:addMark];

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
    [goMenu addItem:hideHK];

    goItem.submenu = goMenu;
    [mainMenu addItem:goItem];

    // 窗口菜单（系统标准）
    NSMenuItem* windowItem = [[NSMenuItem alloc] init];
    NSMenu* windowMenu = [[NSMenu alloc] initWithTitle:@"窗口"];
    [windowMenu addItemWithTitle:@"最小化"
                          action:@selector(performMiniaturize:)
                   keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"缩放"
                          action:@selector(performZoom:)
                   keyEquivalent:@""];
    windowItem.submenu = windowMenu;
    NSApp.windowsMenu = windowMenu;
    [mainMenu addItem:windowItem];

    // 帮助菜单
    NSMenuItem* helpItem = [[NSMenuItem alloc] init];
    NSMenu* helpMenu = [[NSMenu alloc] initWithTitle:@"帮助"];
    NSMenuItem* repo = [[NSMenuItem alloc] initWithTitle:@"打开项目主页…"
                                                   action:@selector(openHomepage:)
                                            keyEquivalent:@""];
    repo.target = self;
    [helpMenu addItem:repo];
    helpItem.submenu = helpMenu;
    NSApp.helpMenu = helpMenu;
    [mainMenu addItem:helpItem];

    NSApp.mainMenu = mainMenu;
}

- (void)openHomepage:(id)sender {
    [NSWorkspace.sharedWorkspace
        openURL:[NSURL URLWithString:@"https://github.com/WeirdoMeng/Reader-Mac"]];
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
            NSString* title = [NSString stringWithFormat:@"%@", path.lastPathComponent];
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

- (void)openRecent:(NSMenuItem*)sender {
    NSString* path = sender.representedObject;
    if (path && [NSFileManager.defaultManager fileExistsAtPath:path]) {
        [self.canvas openFileAtPath:path];
        self.window.title = path.lastPathComponent;
    }
}

- (void)clearRecent:(id)sender {
    [ReaderCanvasView clearRecentBooks];
}

// ---------- View toggles ----------

- (void)openPreferences:(id)sender {
    if (!self.prefs) {
        self.prefs = [[PreferencesWindowController alloc] initWithCanvas:self.canvas];
    }
    [self.prefs showWindow:nil];
    [self.prefs.window center];
    // 子窗口跟随主窗口的置顶状态
    self.prefs.window.level = self.topMost ? NSFloatingWindowLevel : NSNormalWindowLevel;
    [self.prefs.window makeKeyAndOrderFront:nil];

    // 监听 prefs 关闭，确保主窗口重新成为 keyWindow + canvas 重新成为 firstResponder
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                   name:NSWindowWillCloseNotification
                                                 object:self.prefs.window];
    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(prefsWindowWillClose:)
               name:NSWindowWillCloseNotification
             object:self.prefs.window];
}

- (void)prefsWindowWillClose:(NSNotification*)note {
    // 延迟一帧让 prefs 真正关掉，再把焦点回到主窗口的 canvas
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.window makeKeyAndOrderFront:nil];
        [self.window makeFirstResponder:self.canvas];
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

@end

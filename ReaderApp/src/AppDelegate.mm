#import "AppDelegate.h"
#import "GlobalHotkey.h"
#import "PreferencesWindowController.h"
#import "ReaderCanvasView.h"

@interface AppDelegate () <NSMenuDelegate>
@property (strong) NSWindow* window;
@property (strong) ReaderCanvasView* canvas;
@property (assign) NSWindowStyleMask savedStyleMask;
@property (assign) BOOL borderless;
@property (assign) BOOL topMost;
@property (strong) PreferencesWindowController* prefs;
@property (strong) NSMenu* chaptersMenu;
@property (strong) NSMenu* bookmarksMenu;
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
    self.window.title = @"Reader-Mac";
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

    // Register global Option+H to toggle show/hide
    __weak typeof(self) ws = self;
    [GlobalHotkey registerHotkeyWithBlock:^{
        [ws toggleShowHide];
    }];
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

    // App menu (with About / Quit)
    NSMenuItem* appItem = [[NSMenuItem alloc] init];
    NSMenu* appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"About Reader-Mac"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    NSMenuItem* prefs = [[NSMenuItem alloc] initWithTitle:@"Preferences…"
                                                    action:@selector(openPreferences:)
                                             keyEquivalent:@","];
    prefs.target = self;
    [appMenu addItem:prefs];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Reader-Mac"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];

    // File menu
    NSMenuItem* fileItem = [[NSMenuItem alloc] init];
    NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    NSMenuItem* open = [[NSMenuItem alloc] initWithTitle:@"Open…"
                                                  action:@selector(openDocument:)
                                           keyEquivalent:@"o"];
    open.target = self;
    [fileMenu addItem:open];
    NSMenuItem* close = [[NSMenuItem alloc] initWithTitle:@"Close"
                                                   action:@selector(closeDocument:)
                                            keyEquivalent:@"w"];
    close.target = self;
    [fileMenu addItem:close];
    fileItem.submenu = fileMenu;
    [mainMenu addItem:fileItem];

    // View menu
    NSMenuItem* viewItem = [[NSMenuItem alloc] init];
    NSMenu* viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem* borderless = [[NSMenuItem alloc] initWithTitle:@"Toggle Borderless"
                                                         action:@selector(toggleBorderless:)
                                                  keyEquivalent:@"b"];
    borderless.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    borderless.target = self;
    [viewMenu addItem:borderless];
    NSMenuItem* fullscreen = [[NSMenuItem alloc] initWithTitle:@"Toggle Full Screen"
                                                         action:@selector(toggleFullScreen:)
                                                  keyEquivalent:@"f"];
    fullscreen.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    fullscreen.target = self;
    [viewMenu addItem:fullscreen];
    NSMenuItem* top = [[NSMenuItem alloc] initWithTitle:@"Keep on Top"
                                                  action:@selector(toggleTopMost:)
                                           keyEquivalent:@"t"];
    top.target = self;
    [viewMenu addItem:top];
    viewItem.submenu = viewMenu;
    [mainMenu addItem:viewItem];

    // Go menu (chapters + bookmarks)
    NSMenuItem* goItem = [[NSMenuItem alloc] init];
    NSMenu* goMenu = [[NSMenu alloc] initWithTitle:@"Go"];
    NSMenuItem* prevCh = [[NSMenuItem alloc] initWithTitle:@"Previous Chapter"
                                                     action:@selector(jumpPrevChapter:)
                                              keyEquivalent:@"["];
    prevCh.target = self;
    [goMenu addItem:prevCh];
    NSMenuItem* nextCh = [[NSMenuItem alloc] initWithTitle:@"Next Chapter"
                                                     action:@selector(jumpNextChapter:)
                                              keyEquivalent:@"]"];
    nextCh.target = self;
    [goMenu addItem:nextCh];
    [goMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* chaptersItem = [[NSMenuItem alloc] initWithTitle:@"Chapters"
                                                           action:nil
                                                    keyEquivalent:@""];
    self.chaptersMenu = [[NSMenu alloc] initWithTitle:@"Chapters"];
    self.chaptersMenu.delegate = self;
    chaptersItem.submenu = self.chaptersMenu;
    [goMenu addItem:chaptersItem];

    [goMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* addMark = [[NSMenuItem alloc] initWithTitle:@"Add Bookmark"
                                                      action:@selector(addBookmark:)
                                               keyEquivalent:@"m"];
    addMark.target = self;
    [goMenu addItem:addMark];

    NSMenuItem* bookmarksItem = [[NSMenuItem alloc] initWithTitle:@"Bookmarks"
                                                            action:nil
                                                     keyEquivalent:@""];
    self.bookmarksMenu = [[NSMenu alloc] initWithTitle:@"Bookmarks"];
    self.bookmarksMenu.delegate = self;
    bookmarksItem.submenu = self.bookmarksMenu;
    [goMenu addItem:bookmarksItem];

    goItem.submenu = goMenu;
    [mainMenu addItem:goItem];

    NSApp.mainMenu = mainMenu;
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
    if (menu == self.chaptersMenu) {
        [menu removeAllItems];
        NSArray<NSDictionary*>* chs = [self.canvas chapters];
        if (chs.count == 0) {
            NSMenuItem* none = [[NSMenuItem alloc] initWithTitle:@"(no chapters)"
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
            NSMenuItem* none = [[NSMenuItem alloc] initWithTitle:@"(no bookmarks)"
                                                           action:nil
                                                    keyEquivalent:@""];
            none.enabled = NO;
            [menu addItem:none];
            return;
        }
        int total = 0;
        for (NSNumber* n in marks) {
            int idx = n.intValue;
            NSString* title = [NSString stringWithFormat:@"@ char %d", idx];
            NSMenuItem* mi = [[NSMenuItem alloc] initWithTitle:title
                                                         action:@selector(jumpToBookmark:)
                                                  keyEquivalent:@""];
            mi.target = self;
            mi.tag = idx;
            [menu addItem:mi];
            ++total;
        }
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem* clear = [[NSMenuItem alloc] initWithTitle:@"Clear All Bookmarks"
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

// ---------- View toggles ----------

- (void)openPreferences:(id)sender {
    if (!self.prefs) {
        self.prefs = [[PreferencesWindowController alloc] initWithCanvas:self.canvas];
    }
    [self.prefs showWindow:nil];
    [self.prefs.window center];
    [self.prefs.window makeKeyAndOrderFront:nil];
}

- (void)toggleBorderless:(id)sender {
    self.borderless = !self.borderless;
    NSRect frame = self.window.frame;
    if (self.borderless) {
        self.savedStyleMask = self.window.styleMask;
        self.window.styleMask = NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable;
        self.window.titleVisibility = NSWindowTitleHidden;
    } else {
        self.window.styleMask = self.savedStyleMask;
        self.window.titleVisibility = NSWindowTitleVisible;
        self.window.title = self.canvas ? self.window.title : @"Reader-Mac";
    }
    [self.window setFrame:frame display:YES];
    [self.window makeFirstResponder:self.canvas];
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
}

- (void)openDocument:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
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
    self.window.title = @"Reader-Mac";
}

- (BOOL)application:(NSApplication*)sender openFile:(NSString*)filename {
    [self.canvas openFileAtPath:filename];
    self.window.title = filename.lastPathComponent;
    return YES;
}

@end

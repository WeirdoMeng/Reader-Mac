#import "AppDelegate.h"
#import "ReaderCanvasView.h"

@interface AppDelegate ()
@property (strong) NSWindow* window;
@property (strong) ReaderCanvasView* canvas;
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
    [self.window makeKeyAndOrderFront:nil];

    [self installMenu];
    [NSApp activateIgnoringOtherApps:YES];
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

    NSApp.mainMenu = mainMenu;
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

#import "PreferencesWindowController.h"
#import "KeyBindings.h"
#import "KeyRecorderButton.h"
#import "ReaderCanvasView.h"

// =====================================================================
//                          DISPLAY SETTINGS VIEW
// =====================================================================

@interface DisplaySettingsView : NSView
@property (weak)   ReaderCanvasView* canvas;
@property (strong) NSStepper*  fontStepper;
@property (strong) NSTextField* fontValueLabel;
@property (strong) NSStepper*  lineGapStepper;
@property (strong) NSTextField* lineGapValueLabel;
@property (strong) NSStepper*  paraGapStepper;
@property (strong) NSTextField* paraGapValueLabel;
@property (strong) NSButton*   indentCheckbox;
@property (strong) NSColorWell* textColorWell;
@property (strong) NSColorWell* bgColorWell;
@end

@implementation DisplaySettingsView

- (instancetype)initWithCanvas:(ReaderCanvasView*)canvas {
    self = [super initWithFrame:NSMakeRect(0, 0, 360, 260)];
    if (self) {
        _canvas = canvas;
        [self buildUI];
    }
    return self;
}

- (NSTextField*)label:(NSString*)s {
    NSTextField* t = [NSTextField labelWithString:s];
    t.font = [NSFont systemFontOfSize:13];
    return t;
}

- (void)buildUI {
    CGFloat y = 220;
    const CGFloat L = 20, COL2 = 160, COL3 = 250;

    NSTextField* l1 = [self label:@"字体大小"]; l1.frame = NSMakeRect(L, y, 120, 22); [self addSubview:l1];
    self.fontStepper = [[NSStepper alloc] initWithFrame:NSMakeRect(COL3, y, 28, 22)];
    self.fontStepper.minValue = 8; self.fontStepper.maxValue = 64;
    self.fontStepper.integerValue = [self.canvas fontSize];
    self.fontStepper.target = self; self.fontStepper.action = @selector(fontChanged:);
    [self addSubview:self.fontStepper];
    self.fontValueLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%d pt", [self.canvas fontSize]]];
    self.fontValueLabel.frame = NSMakeRect(COL2, y, 80, 22);
    [self addSubview:self.fontValueLabel];

    y -= 36;
    NSTextField* l2 = [self label:@"行距"]; l2.frame = NSMakeRect(L, y, 120, 22); [self addSubview:l2];
    self.lineGapStepper = [[NSStepper alloc] initWithFrame:NSMakeRect(COL3, y, 28, 22)];
    self.lineGapStepper.minValue = 0; self.lineGapStepper.maxValue = 40;
    self.lineGapStepper.integerValue = [self.canvas lineGap];
    self.lineGapStepper.target = self; self.lineGapStepper.action = @selector(lineGapChanged:);
    [self addSubview:self.lineGapStepper];
    self.lineGapValueLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%d px", [self.canvas lineGap]]];
    self.lineGapValueLabel.frame = NSMakeRect(COL2, y, 80, 22);
    [self addSubview:self.lineGapValueLabel];

    y -= 36;
    NSTextField* l3 = [self label:@"段距"]; l3.frame = NSMakeRect(L, y, 120, 22); [self addSubview:l3];
    self.paraGapStepper = [[NSStepper alloc] initWithFrame:NSMakeRect(COL3, y, 28, 22)];
    self.paraGapStepper.minValue = 0; self.paraGapStepper.maxValue = 80;
    self.paraGapStepper.integerValue = [self.canvas paragraphGap];
    self.paraGapStepper.target = self; self.paraGapStepper.action = @selector(paraGapChanged:);
    [self addSubview:self.paraGapStepper];
    self.paraGapValueLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%d px", [self.canvas paragraphGap]]];
    self.paraGapValueLabel.frame = NSMakeRect(COL2, y, 80, 22);
    [self addSubview:self.paraGapValueLabel];

    y -= 36;
    self.indentCheckbox = [NSButton checkboxWithTitle:@"首行缩进"
                                                target:self
                                                action:@selector(indentChanged:)];
    self.indentCheckbox.frame = NSMakeRect(L, y, 200, 22);
    self.indentCheckbox.state = [self.canvas firstLineIndent] ? NSControlStateValueOn : NSControlStateValueOff;
    [self addSubview:self.indentCheckbox];

    y -= 36;
    NSTextField* l4 = [self label:@"文字颜色"]; l4.frame = NSMakeRect(L, y, 120, 22); [self addSubview:l4];
    self.textColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(COL3 - 30, y, 60, 22)];
    self.textColorWell.color = [self.canvas textColor];
    self.textColorWell.target = self; self.textColorWell.action = @selector(textColorChanged:);
    [self addSubview:self.textColorWell];

    y -= 36;
    NSTextField* l5 = [self label:@"背景颜色"]; l5.frame = NSMakeRect(L, y, 120, 22); [self addSubview:l5];
    self.bgColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(COL3 - 30, y, 60, 22)];
    self.bgColorWell.color = [self.canvas backgroundColor];
    self.bgColorWell.target = self; self.bgColorWell.action = @selector(bgColorChanged:);
    [self addSubview:self.bgColorWell];
}

- (void)fontChanged:(NSStepper*)s {
    [self.canvas setFontSize:(int)s.integerValue];
    self.fontValueLabel.stringValue = [NSString stringWithFormat:@"%d pt", (int)s.integerValue];
}
- (void)lineGapChanged:(NSStepper*)s {
    [self.canvas setLineGap:(int)s.integerValue];
    self.lineGapValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)s.integerValue];
}
- (void)paraGapChanged:(NSStepper*)s {
    [self.canvas setParagraphGap:(int)s.integerValue];
    self.paraGapValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)s.integerValue];
}
- (void)indentChanged:(NSButton*)b {
    [self.canvas setFirstLineIndent:b.state == NSControlStateValueOn];
}
- (void)textColorChanged:(NSColorWell*)cw { [self.canvas setTextColor:cw.color]; }
- (void)bgColorChanged:(NSColorWell*)cw { [self.canvas setBackgroundColor:cw.color]; }
@end

// =====================================================================
//                           SHORTCUTS VIEW
// =====================================================================

@interface ShortcutsView : NSView <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSTableView* table;
@property (strong) NSArray<KBAction*>* actions;
@property (strong) NSMutableDictionary<NSString*, KeyRecorderButton*>* recorders;
@end

@implementation ShortcutsView

- (instancetype)init {
    self = [super initWithFrame:NSMakeRect(0, 0, 460, 320)];
    if (self) {
        _recorders = [NSMutableDictionary dictionary];
        [self reloadActions];
        [self buildUI];
        [NSNotificationCenter.defaultCenter
            addObserver:self selector:@selector(bindingsChanged:)
                   name:KeyBindingsDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)reloadActions {
    self.actions = [KeyBindings.shared allActions];
}

- (void)bindingsChanged:(NSNotification*)note {
    [self reloadActions];
    for (KBAction* a in self.actions) {
        KeyRecorderButton* btn = self.recorders[a.actionId];
        if (btn) [btn setShortcut:a.shortcut];
    }
    [self.table reloadData];
}

- (void)buildUI {
    NSScrollView* sv = [[NSScrollView alloc]
                           initWithFrame:NSMakeRect(10, 50, 440, 260)];
    sv.hasVerticalScroller = YES;
    sv.borderType = NSBezelBorder;

    self.table = [[NSTableView alloc] initWithFrame:sv.bounds];
    self.table.rowHeight = 30;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.allowsColumnResizing = YES;

    NSTableColumn* c1 = [[NSTableColumn alloc] initWithIdentifier:@"action"];
    c1.title = @"动作"; c1.width = 220;
    [self.table addTableColumn:c1];

    NSTableColumn* c2 = [[NSTableColumn alloc] initWithIdentifier:@"shortcut"];
    c2.title = @"快捷键"; c2.width = 200;
    [self.table addTableColumn:c2];

    sv.documentView = self.table;
    [self addSubview:sv];

    NSButton* resetAll = [NSButton buttonWithTitle:@"恢复全部默认"
                                              target:self
                                              action:@selector(resetAll:)];
    resetAll.frame = NSMakeRect(10, 12, 140, 28);
    [self addSubview:resetAll];

    NSTextField* tip = [NSTextField labelWithString:@"提示：点击右侧按钮，按下新组合即生效。Esc 取消。"];
    tip.font = [NSFont systemFontOfSize:11];
    tip.textColor = [NSColor secondaryLabelColor];
    tip.frame = NSMakeRect(160, 16, 300, 16);
    [self addSubview:tip];
}

- (void)resetAll:(id)sender {
    [KeyBindings.shared resetAllToDefault];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tv { return self.actions.count; }

- (NSView*)tableView:(NSTableView*)tv
   viewForTableColumn:(NSTableColumn*)col
                  row:(NSInteger)row {
    KBAction* a = self.actions[row];
    if ([col.identifier isEqualToString:@"action"]) {
        NSTextField* tf = [NSTextField labelWithString:a.displayName];
        tf.font = [NSFont systemFontOfSize:13];
        return tf;
    } else {
        KeyRecorderButton* btn = self.recorders[a.actionId];
        if (!btn) {
            btn = [[KeyRecorderButton alloc] initWithFrame:NSMakeRect(0, 0, 180, 24)];
            self.recorders[a.actionId] = btn;
            __weak typeof(btn) wbtn = btn;
            NSString* aid = a.actionId;
            btn.onRecorded = ^(KBShortcut* sc) {
                [KeyBindings.shared setShortcut:sc forActionId:aid];
                (void)wbtn;
            };
        }
        [btn setShortcut:a.shortcut];
        return btn;
    }
}

@end

// =====================================================================
//                       PREFERENCES WINDOW CONTROLLER
// =====================================================================

@interface PreferencesWindowController ()
@property (weak)   ReaderCanvasView* canvas;
@end

@implementation PreferencesWindowController

- (instancetype)initWithCanvas:(ReaderCanvasView*)canvas {
    NSRect frame = NSMakeRect(0, 0, 500, 380);
    NSWindow* w = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled
                                                         | NSWindowStyleMaskClosable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    w.title = @"偏好设置";
    self = [super initWithWindow:w];
    if (self) {
        _canvas = canvas;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    NSTabView* tabs = [[NSTabView alloc] initWithFrame:self.window.contentView.bounds];
    tabs.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSTabViewItem* tab1 = [[NSTabViewItem alloc] initWithIdentifier:@"display"];
    tab1.label = @"显示设置";
    tab1.view = [[DisplaySettingsView alloc] initWithCanvas:self.canvas];
    [tabs addTabViewItem:tab1];

    NSTabViewItem* tab2 = [[NSTabViewItem alloc] initWithIdentifier:@"shortcuts"];
    tab2.label = @"快捷键";
    tab2.view = [[ShortcutsView alloc] init];
    [tabs addTabViewItem:tab2];

    [self.window.contentView addSubview:tabs];
}
@end

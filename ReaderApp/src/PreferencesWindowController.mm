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
    self = [super initWithFrame:NSMakeRect(0, 0, 480, 360)];
    if (self) {
        _canvas = canvas;
        [self buildUI];
    }
    return self;
}

- (NSTextField*)labelKey:(NSString*)s {
    NSTextField* t = [NSTextField labelWithString:s];
    t.font = [NSFont systemFontOfSize:13];
    t.textColor = [NSColor secondaryLabelColor];
    t.alignment = NSTextAlignmentRight;
    return t;
}

- (NSTextField*)valueLabel:(NSString*)s {
    NSTextField* t = [NSTextField labelWithString:s];
    t.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
    return t;
}

- (NSView*)makeStepperRowMin:(double)min
                          max:(double)max
                        value:(double)v
                       suffix:(NSString*)suffix
                       action:(SEL)sel
                  ivarStepper:(NSStepper* __strong *)stepperIvar
                    ivarLabel:(NSTextField* __strong *)labelIvar {
    NSStepper* st = [[NSStepper alloc] initWithFrame:NSMakeRect(0, 0, 28, 22)];
    st.minValue = min; st.maxValue = max;
    st.integerValue = (int)v;
    st.target = self; st.action = sel;

    NSTextField* lab = [self valueLabel:[NSString stringWithFormat:@"%d %@", (int)v, suffix]];

    NSStackView* row = [NSStackView stackViewWithViews:@[lab, st]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 8;
    row.alignment = NSLayoutAttributeCenterY;

    *stepperIvar = st;
    *labelIvar   = lab;
    return row;
}

- (void)buildUI {
    NSGridView* grid = [[NSGridView alloc] initWithFrame:NSMakeRect(20, 20, 440, 320)];
    grid.rowSpacing = 14;
    grid.columnSpacing = 16;

    // 字体大小
    NSStepper* st1 = nil; NSTextField* lb1 = nil;
    NSView* row1 = [self makeStepperRowMin:8 max:64 value:[self.canvas fontSize]
                                    suffix:@"pt"
                                    action:@selector(fontChanged:)
                               ivarStepper:&st1 ivarLabel:&lb1];
    self.fontStepper = st1; self.fontValueLabel = lb1;
    [grid addRowWithViews:@[[self labelKey:@"字体大小"], row1]];

    // 行距
    NSStepper* st2 = nil; NSTextField* lb2 = nil;
    NSView* row2 = [self makeStepperRowMin:0 max:40 value:[self.canvas lineGap]
                                    suffix:@"px"
                                    action:@selector(lineGapChanged:)
                               ivarStepper:&st2 ivarLabel:&lb2];
    self.lineGapStepper = st2; self.lineGapValueLabel = lb2;
    [grid addRowWithViews:@[[self labelKey:@"行  距"], row2]];

    // 段距
    NSStepper* st3 = nil; NSTextField* lb3 = nil;
    NSView* row3 = [self makeStepperRowMin:0 max:80 value:[self.canvas paragraphGap]
                                    suffix:@"px"
                                    action:@selector(paraGapChanged:)
                               ivarStepper:&st3 ivarLabel:&lb3];
    self.paraGapStepper = st3; self.paraGapValueLabel = lb3;
    [grid addRowWithViews:@[[self labelKey:@"段  距"], row3]];

    // 首行缩进
    self.indentCheckbox = [NSButton checkboxWithTitle:@"开启首行缩进"
                                                target:self
                                                action:@selector(indentChanged:)];
    self.indentCheckbox.state = [self.canvas firstLineIndent] ? NSControlStateValueOn : NSControlStateValueOff;
    [grid addRowWithViews:@[[self labelKey:@"首行缩进"], self.indentCheckbox]];

    // 文字颜色
    self.textColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 64, 24)];
    self.textColorWell.color = [self.canvas textColor];
    self.textColorWell.target = self; self.textColorWell.action = @selector(textColorChanged:);
    [grid addRowWithViews:@[[self labelKey:@"文字颜色"], self.textColorWell]];

    // 背景颜色
    self.bgColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 64, 24)];
    self.bgColorWell.color = [self.canvas backgroundColor];
    self.bgColorWell.target = self; self.bgColorWell.action = @selector(bgColorChanged:);
    [grid addRowWithViews:@[[self labelKey:@"背景颜色"], self.bgColorWell]];

    // 列对齐
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;
    for (NSInteger i = 0; i < grid.numberOfRows; ++i) {
        [grid rowAtIndex:i].yPlacement = NSGridCellPlacementCenter;
    }
    [grid columnAtIndex:0].width = 90;

    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:grid];
    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor      constraintEqualToAnchor:self.topAnchor      constant:24],
        [grid.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor  constant:24],
        [grid.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24],
    ]];

    NSTextField* tip = [NSTextField labelWithString:@"修改即时生效，并自动保存。下次启动恢复。"];
    tip.font = [NSFont systemFontOfSize:11];
    tip.textColor = [NSColor secondaryLabelColor];
    tip.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:tip];
    [NSLayoutConstraint activateConstraints:@[
        [tip.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24],
        [tip.bottomAnchor  constraintEqualToAnchor:self.bottomAnchor  constant:-16],
    ]];
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
- (void)stopAllRecording;
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

    // 恢复默认按钮 + 提示
    NSButton* resetAll = [NSButton buttonWithTitle:@"恢复全部默认"
                                              target:self
                                              action:@selector(resetAll:)];
    resetAll.frame = NSMakeRect(10, 12, 130, 28);
    [self addSubview:resetAll];

    NSTextField* tip = [NSTextField labelWithString:@"提示：点击按钮录入新组合，按下即生效。Esc 取消。"];
    tip.font = [NSFont systemFontOfSize:11];
    tip.textColor = [NSColor secondaryLabelColor];
    tip.frame = NSMakeRect(150, 16, 310, 16);
    [self addSubview:tip];
}

- (void)resetAll:(id)sender {
    [KeyBindings.shared resetAllToDefault];
}

- (void)stopAllRecording {
    for (KeyRecorderButton* btn in self.recorders.allValues) {
        [btn stopRecording];
    }
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
                // 录入后立即生效
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

@interface PreferencesWindowController () <NSWindowDelegate>
@property (weak)   ReaderCanvasView* canvas;
@property (strong) ShortcutsView*    shortcutsView;
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
        w.delegate = self;
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
    self.shortcutsView = [[ShortcutsView alloc] init];
    tab2.view = self.shortcutsView;
    [tabs addTabViewItem:tab2];

    [self.window.contentView addSubview:tabs];
}

// CRITICAL: when the user closes the prefs window mid-recording, the
// KeyRecorderButton's NSEvent monitor would otherwise stay alive and
// swallow every keyDown system-wide (including arrow keys). Force-stop
// any in-progress recording on close.
- (void)windowWillClose:(NSNotification*)note {
    [self.shortcutsView stopAllRecording];
}
@end

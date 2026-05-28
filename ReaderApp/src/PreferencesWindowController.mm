#import "PreferencesWindowController.h"
#import "KeyBindings.h"
#import "KeyRecorderButton.h"
#import "ReaderCanvasView.h"

// =====================================================================
//                          DISPLAY SETTINGS VIEW
// =====================================================================

@interface DisplaySettingsView : NSView
@property (weak)   ReaderCanvasView* canvas;
@property (strong) NSSlider*    fontSlider;
@property (strong) NSTextField* fontValueLabel;
@property (strong) NSSlider*    charGapSlider;
@property (strong) NSTextField* charGapValueLabel;
@property (strong) NSSlider*    lineGapSlider;
@property (strong) NSTextField* lineGapValueLabel;
@property (strong) NSSlider*    paraGapSlider;
@property (strong) NSTextField* paraGapValueLabel;
@property (strong) NSButton*    indentSwitch;
@property (strong) NSColorWell* textColorWell;
@property (strong) NSColorWell* bgColorWell;
@end

@implementation DisplaySettingsView

- (instancetype)initWithCanvas:(ReaderCanvasView*)canvas {
    self = [super initWithFrame:NSMakeRect(0, 0, 500, 380)];
    if (self) {
        _canvas = canvas;
        [self buildUI];
    }
    return self;
}

// ---- small UI helpers ----

- (NSTextField*)sectionTitle:(NSString*)s {
    NSTextField* t = [NSTextField labelWithString:s];
    t.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    t.textColor = [NSColor secondaryLabelColor];
    return t;
}

- (NSTextField*)rowLabel:(NSString*)s {
    NSTextField* t = [NSTextField labelWithString:s];
    t.font = [NSFont systemFontOfSize:13];
    t.alignment = NSTextAlignmentRight;
    return t;
}

- (NSTextField*)valueChip:(NSString*)s {
    NSTextField* t = [NSTextField labelWithString:s];
    t.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium];
    t.textColor = [NSColor secondaryLabelColor];
    t.alignment = NSTextAlignmentRight;
    return t;
}

- (NSBox*)separator {
    NSBox* sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    return sep;
}

// row = label + slider + value chip
- (NSView*)sliderRow:(NSString*)labelText
                 min:(double)min
                 max:(double)max
               value:(double)v
              suffix:(NSString*)suffix
              action:(SEL)sel
              slider:(NSSlider* __strong *)sliderOut
               chip:(NSTextField* __strong *)chipOut
            outLabel:(NSTextField* __strong *)labelOut {
    NSTextField* lab = [self rowLabel:labelText];
    lab.translatesAutoresizingMaskIntoConstraints = NO;

    NSSlider* sl = [NSSlider sliderWithValue:v minValue:min maxValue:max
                                       target:self action:sel];
    sl.numberOfTickMarks = (int)((max - min) >= 20 ? 5 : (max - min) + 1);
    sl.allowsTickMarkValuesOnly = NO;
    sl.translatesAutoresizingMaskIntoConstraints = NO;
    [sl.widthAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;

    NSTextField* chip = [self valueChip:[NSString stringWithFormat:@"%d %@", (int)v, suffix]];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    [chip.widthAnchor constraintEqualToConstant:50].active = YES;

    NSStackView* row = [NSStackView stackViewWithViews:@[lab, sl, chip]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 12;
    row.alignment = NSLayoutAttributeCenterY;
    row.distribution = NSStackViewDistributionFill;

    [lab.widthAnchor constraintEqualToConstant:64].active = YES;
    [row setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [sl  setContentHuggingPriority:NSLayoutPriorityDefaultLow
                  forOrientation:NSLayoutConstraintOrientationHorizontal];

    *sliderOut = sl;
    *chipOut   = chip;
    *labelOut  = lab;
    return row;
}

- (NSView*)checkboxRow:(NSString*)labelText
              checkbox:(NSButton*)cb {
    NSTextField* lab = [self rowLabel:labelText];
    [lab.widthAnchor constraintEqualToConstant:64].active = YES;
    NSStackView* row = [NSStackView stackViewWithViews:@[lab, cb]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 12;
    row.alignment = NSLayoutAttributeCenterY;
    return row;
}

- (NSView*)colorRow:(NSString*)labelText well:(NSColorWell*)well {
    NSTextField* lab = [self rowLabel:labelText];
    [lab.widthAnchor constraintEqualToConstant:64].active = YES;
    [well.widthAnchor constraintEqualToConstant:60].active = YES;
    [well.heightAnchor constraintEqualToConstant:24].active = YES;
    NSStackView* row = [NSStackView stackViewWithViews:@[lab, well]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 12;
    row.alignment = NSLayoutAttributeCenterY;
    return row;
}

- (void)buildUI {
    // ---- 排版分组 ----
    NSTextField* secTypo = [self sectionTitle:@"排版"];

    NSSlider* s1; NSTextField* c1; NSTextField* l1;
    NSView* r1 = [self sliderRow:@"字体大小" min:8 max:48 value:[self.canvas fontSize]
                          suffix:@"pt" action:@selector(fontChanged:)
                          slider:&s1 chip:&c1 outLabel:&l1];
    self.fontSlider = s1; self.fontValueLabel = c1;

    NSSlider* s0; NSTextField* c0; NSTextField* l0;
    NSView* r0 = [self sliderRow:@"字  距" min:0 max:10 value:[self.canvas charGap]
                          suffix:@"px" action:@selector(charGapChanged:)
                          slider:&s0 chip:&c0 outLabel:&l0];
    self.charGapSlider = s0; self.charGapValueLabel = c0;

    NSSlider* s2; NSTextField* c2; NSTextField* l2;
    NSView* r2 = [self sliderRow:@"行  距" min:0 max:30 value:[self.canvas lineGap]
                          suffix:@"px" action:@selector(lineGapChanged:)
                          slider:&s2 chip:&c2 outLabel:&l2];
    self.lineGapSlider = s2; self.lineGapValueLabel = c2;

    NSSlider* s3; NSTextField* c3; NSTextField* l3;
    NSView* r3 = [self sliderRow:@"段  距" min:0 max:60 value:[self.canvas paragraphGap]
                          suffix:@"px" action:@selector(paraGapChanged:)
                          slider:&s3 chip:&c3 outLabel:&l3];
    self.paraGapSlider = s3; self.paraGapValueLabel = c3;

    self.indentSwitch = [NSButton checkboxWithTitle:@"开启首行缩进"
                                              target:self
                                              action:@selector(indentChanged:)];
    self.indentSwitch.state = [self.canvas firstLineIndent] ?
        NSControlStateValueOn : NSControlStateValueOff;
    NSView* r4 = [self checkboxRow:@"首行缩进" checkbox:self.indentSwitch];

    // ---- 颜色分组 ----
    NSTextField* secColor = [self sectionTitle:@"颜色"];

    self.textColorWell = [[NSColorWell alloc] init];
    self.textColorWell.color = [self.canvas textColor];
    self.textColorWell.target = self;
    self.textColorWell.action = @selector(textColorChanged:);
    NSView* r5 = [self colorRow:@"文字颜色" well:self.textColorWell];

    self.bgColorWell = [[NSColorWell alloc] init];
    self.bgColorWell.color = [self.canvas backgroundColor];
    self.bgColorWell.target = self;
    self.bgColorWell.action = @selector(bgColorChanged:);
    NSView* r6 = [self colorRow:@"背景颜色" well:self.bgColorWell];

    // 颜色重置按钮
    NSButton* resetColors = [NSButton buttonWithTitle:@"恢复系统配色"
                                                 target:self
                                                 action:@selector(resetColors:)];
    resetColors.bezelStyle = NSBezelStyleRoundRect;
    resetColors.controlSize = NSControlSizeSmall;

    // ---- 主 stack 垂直排列 ----
    NSStackView* main = [NSStackView stackViewWithViews:@[
        secTypo, r1, r0, r2, r3, r4,
        [self separator],
        secColor, r5, r6, resetColors,
    ]];
    main.orientation = NSUserInterfaceLayoutOrientationVertical;
    main.alignment = NSLayoutAttributeLeading;
    main.spacing = 12;
    main.translatesAutoresizingMaskIntoConstraints = NO;

    // 给每一行设宽度约束（一致宽）
    for (NSView* row in @[r1, r0, r2, r3, r4, r5, r6]) {
        row.translatesAutoresizingMaskIntoConstraints = NO;
    }
    [self addSubview:main];

    [NSLayoutConstraint activateConstraints:@[
        [main.topAnchor      constraintEqualToAnchor:self.topAnchor      constant:20],
        [main.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor  constant:24],
        [main.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24],
    ]];
    for (NSView* row in @[r1, r0, r2, r3]) {
        [row.leadingAnchor  constraintEqualToAnchor:main.leadingAnchor].active = YES;
        [row.trailingAnchor constraintEqualToAnchor:main.trailingAnchor].active = YES;
    }

    // 底部提示
    NSTextField* tip = [NSTextField labelWithString:@"修改即时生效并自动保存，下次启动恢复。"];
    tip.font = [NSFont systemFontOfSize:11];
    tip.textColor = [NSColor tertiaryLabelColor];
    tip.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:tip];
    [NSLayoutConstraint activateConstraints:@[
        [tip.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24],
        [tip.bottomAnchor  constraintEqualToAnchor:self.bottomAnchor  constant:-14],
    ]];
}

- (void)fontChanged:(NSSlider*)s {
    int v = (int)round(s.doubleValue);
    [self.canvas setFontSize:v];
    self.fontValueLabel.stringValue = [NSString stringWithFormat:@"%d pt", v];
}
- (void)charGapChanged:(NSSlider*)s {
    int v = (int)round(s.doubleValue);
    [self.canvas setCharGap:v];
    self.charGapValueLabel.stringValue = [NSString stringWithFormat:@"%d px", v];
}
- (void)lineGapChanged:(NSSlider*)s {
    int v = (int)round(s.doubleValue);
    [self.canvas setLineGap:v];
    self.lineGapValueLabel.stringValue = [NSString stringWithFormat:@"%d px", v];
}
- (void)paraGapChanged:(NSSlider*)s {
    int v = (int)round(s.doubleValue);
    [self.canvas setParagraphGap:v];
    self.paraGapValueLabel.stringValue = [NSString stringWithFormat:@"%d px", v];
}
- (void)indentChanged:(NSButton*)b {
    [self.canvas setFirstLineIndent:b.state == NSControlStateValueOn];
}
- (void)textColorChanged:(NSColorWell*)cw { [self.canvas setTextColor:cw.color]; }
- (void)bgColorChanged:(NSColorWell*)cw   { [self.canvas setBackgroundColor:cw.color]; }
- (void)resetColors:(id)sender {
    [self.canvas setTextColor:[NSColor labelColor]];
    [self.canvas setBackgroundColor:[NSColor windowBackgroundColor]];
    self.textColorWell.color = [self.canvas textColor];
    self.bgColorWell.color   = [self.canvas backgroundColor];
}
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

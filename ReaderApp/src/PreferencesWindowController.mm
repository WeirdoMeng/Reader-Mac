#import "PreferencesWindowController.h"
#import "ReaderCanvasView.h"

@interface PreferencesWindowController ()
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

@implementation PreferencesWindowController

- (instancetype)initWithCanvas:(ReaderCanvasView*)canvas {
    NSWindow* w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 340, 280)
                                              styleMask:(NSWindowStyleMaskTitled
                                                         | NSWindowStyleMaskClosable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    w.title = @"显示设置";
    self = [super initWithWindow:w];
    if (self) {
        _canvas = canvas;
        [self buildUI];
    }
    return self;
}

- (NSTextField*)labelWithString:(NSString*)s {
    NSTextField* t = [NSTextField labelWithString:s];
    t.font = [NSFont systemFontOfSize:13];
    return t;
}

- (void)buildUI {
    NSView* root = self.window.contentView;
    CGFloat y = 240;
    const CGFloat L = 20, COL2 = 160, COL3 = 250;

    // 字体大小
    NSTextField* l1 = [self labelWithString:@"字体大小"];
    l1.frame = NSMakeRect(L, y, 120, 22);
    [root addSubview:l1];
    self.fontStepper = [[NSStepper alloc] initWithFrame:NSMakeRect(COL3, y, 28, 22)];
    self.fontStepper.minValue = 8; self.fontStepper.maxValue = 64;
    self.fontStepper.integerValue = [self.canvas fontSize];
    self.fontStepper.target = self;
    self.fontStepper.action = @selector(fontChanged:);
    [root addSubview:self.fontStepper];
    self.fontValueLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%d pt", [self.canvas fontSize]]];
    self.fontValueLabel.frame = NSMakeRect(COL2, y, 80, 22);
    [root addSubview:self.fontValueLabel];

    y -= 36;
    // 行距
    NSTextField* l2 = [self labelWithString:@"行距"];
    l2.frame = NSMakeRect(L, y, 120, 22);
    [root addSubview:l2];
    self.lineGapStepper = [[NSStepper alloc] initWithFrame:NSMakeRect(COL3, y, 28, 22)];
    self.lineGapStepper.minValue = 0; self.lineGapStepper.maxValue = 40;
    self.lineGapStepper.integerValue = [self.canvas lineGap];
    self.lineGapStepper.target = self;
    self.lineGapStepper.action = @selector(lineGapChanged:);
    [root addSubview:self.lineGapStepper];
    self.lineGapValueLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%d px", [self.canvas lineGap]]];
    self.lineGapValueLabel.frame = NSMakeRect(COL2, y, 80, 22);
    [root addSubview:self.lineGapValueLabel];

    y -= 36;
    // 段距
    NSTextField* l3 = [self labelWithString:@"段距"];
    l3.frame = NSMakeRect(L, y, 120, 22);
    [root addSubview:l3];
    self.paraGapStepper = [[NSStepper alloc] initWithFrame:NSMakeRect(COL3, y, 28, 22)];
    self.paraGapStepper.minValue = 0; self.paraGapStepper.maxValue = 80;
    self.paraGapStepper.integerValue = [self.canvas paragraphGap];
    self.paraGapStepper.target = self;
    self.paraGapStepper.action = @selector(paraGapChanged:);
    [root addSubview:self.paraGapStepper];
    self.paraGapValueLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%d px", [self.canvas paragraphGap]]];
    self.paraGapValueLabel.frame = NSMakeRect(COL2, y, 80, 22);
    [root addSubview:self.paraGapValueLabel];

    y -= 36;
    // 首行缩进
    self.indentCheckbox = [NSButton checkboxWithTitle:@"首行缩进"
                                                target:self
                                                action:@selector(indentChanged:)];
    self.indentCheckbox.frame = NSMakeRect(L, y, 200, 22);
    self.indentCheckbox.state = [self.canvas firstLineIndent] ? NSControlStateValueOn : NSControlStateValueOff;
    [root addSubview:self.indentCheckbox];

    y -= 36;
    // 文字颜色
    NSTextField* l4 = [self labelWithString:@"文字颜色"];
    l4.frame = NSMakeRect(L, y, 120, 22);
    [root addSubview:l4];
    self.textColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(COL3 - 30, y, 60, 22)];
    self.textColorWell.color = [self.canvas textColor];
    self.textColorWell.target = self;
    self.textColorWell.action = @selector(textColorChanged:);
    [root addSubview:self.textColorWell];

    y -= 36;
    // 背景颜色
    NSTextField* l5 = [self labelWithString:@"背景颜色"];
    l5.frame = NSMakeRect(L, y, 120, 22);
    [root addSubview:l5];
    self.bgColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(COL3 - 30, y, 60, 22)];
    self.bgColorWell.color = [self.canvas backgroundColor];
    self.bgColorWell.target = self;
    self.bgColorWell.action = @selector(bgColorChanged:);
    [root addSubview:self.bgColorWell];
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
- (void)textColorChanged:(NSColorWell*)cw {
    [self.canvas setTextColor:cw.color];
}
- (void)bgColorChanged:(NSColorWell*)cw {
    [self.canvas setBackgroundColor:cw.color];
}

@end

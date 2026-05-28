#import "ActivationWindowController.h"
#import "License.h"

// =====================================================================
//                     ActivationWindowController
// =====================================================================

@interface ActivationWindowController ()
@property (strong) NSTextField*  uuidField;
@property (strong) NSTextField*  keyField;
@property (strong) NSTextField*  statusLabel;
@end

@implementation ActivationWindowController

+ (instancetype)shared {
    static ActivationWindowController* s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[ActivationWindowController alloc] init]; });
    return s;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 680, 540);
    NSWindow* w = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled
                                                         | NSWindowStyleMaskClosable
                                                         | NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    w.title = @"激活摸鱼书摊";
    [w setContentMinSize:NSMakeSize(680, 540)];
    self = [super initWithWindow:w];
    if (self) [self buildUI];
    return self;
}

- (void)buildUI {
    NSView* root = self.window.contentView;

    // 左侧：二维码 + 说明
    NSImageView* qr = [[NSImageView alloc] init];
    qr.translatesAutoresizingMaskIntoConstraints = NO;
    NSString* qrPath = [NSBundle.mainBundle pathForResource:@"wechat_qr" ofType:@"jpg"];
    qr.image = [[NSImage alloc] initWithContentsOfFile:qrPath];
    qr.imageScaling = NSImageScaleProportionallyUpOrDown;
    qr.wantsLayer = YES;
    qr.layer.cornerRadius = 8;
    qr.layer.borderWidth = 1;
    qr.layer.borderColor = [NSColor separatorColor].CGColor;
    [root addSubview:qr];

    NSTextField* qrTip = [NSTextField wrappingLabelWithString:
        @"购买流程：\n"
        @"1. 微信扫码加好友（备注「摸鱼书摊」）\n"
        @"2. 把「本机识别码」发给作者\n"
        @"3. 付款 ¥66 后获取激活码\n"
        @"4. 把激活码粘贴到右侧 → 激活"];
    qrTip.font = [NSFont systemFontOfSize:12];
    qrTip.textColor = [NSColor secondaryLabelColor];
    qrTip.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:qrTip];

    // 分隔线
    NSBox* sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:sep];

    // 右侧：机器码 + key 输入
    NSTextField* uuidLabel = [NSTextField labelWithString:@"本机识别码（发给作者）"];
    uuidLabel.font = [NSFont boldSystemFontOfSize:12];
    uuidLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:uuidLabel];

    self.uuidField = [[NSTextField alloc] init];
    self.uuidField.stringValue = [License.shared machineUUID];
    self.uuidField.editable = NO;
    self.uuidField.bordered = YES;
    self.uuidField.bezelStyle = NSTextFieldRoundedBezel;
    self.uuidField.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.uuidField.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:self.uuidField];

    NSButton* copyBtn = [NSButton buttonWithTitle:@"复制"
                                            target:self
                                            action:@selector(copyUUID:)];
    copyBtn.bezelStyle = NSBezelStyleRounded;
    copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:copyBtn];

    NSTextField* keyLabel = [NSTextField labelWithString:@"激活码"];
    keyLabel.font = [NSFont boldSystemFontOfSize:12];
    keyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:keyLabel];

    self.keyField = [[NSTextField alloc] init];
    self.keyField.placeholderString = @"MS01-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX";
    self.keyField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.keyField.translatesAutoresizingMaskIntoConstraints = NO;
    self.keyField.target = self;
    self.keyField.action = @selector(activate:);
    [root addSubview:self.keyField];

    NSButton* activateBtn = [NSButton buttonWithTitle:@"激活"
                                                target:self
                                                action:@selector(activate:)];
    activateBtn.bezelStyle = NSBezelStyleRounded;
    activateBtn.keyEquivalent = @"\r";
    activateBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:activateBtn];

    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:self.statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        // 二维码
        [qr.topAnchor      constraintEqualToAnchor:root.topAnchor constant:20],
        [qr.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:20],
        [qr.widthAnchor    constraintEqualToConstant:220],
        [qr.heightAnchor   constraintEqualToConstant:220],

        // 二维码下方说明
        [qrTip.topAnchor      constraintEqualToAnchor:qr.bottomAnchor constant:12],
        [qrTip.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:20],
        [qrTip.trailingAnchor constraintEqualToAnchor:sep.leadingAnchor constant:-12],

        // 分隔线
        [sep.topAnchor      constraintEqualToAnchor:root.topAnchor constant:20],
        [sep.bottomAnchor   constraintEqualToAnchor:root.bottomAnchor constant:-20],
        [sep.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:260],
        [sep.widthAnchor    constraintEqualToConstant:1],

        // 机器码 label + field + copy
        [uuidLabel.topAnchor    constraintEqualToAnchor:root.topAnchor constant:30],
        [uuidLabel.leadingAnchor constraintEqualToAnchor:sep.trailingAnchor constant:20],
        [self.uuidField.topAnchor constraintEqualToAnchor:uuidLabel.bottomAnchor constant:6],
        [self.uuidField.leadingAnchor constraintEqualToAnchor:sep.trailingAnchor constant:20],
        [self.uuidField.trailingAnchor constraintEqualToAnchor:copyBtn.leadingAnchor constant:-8],
        [copyBtn.centerYAnchor constraintEqualToAnchor:self.uuidField.centerYAnchor],
        [copyBtn.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
        [copyBtn.widthAnchor constraintEqualToConstant:60],

        // key label + field
        [keyLabel.topAnchor constraintEqualToAnchor:self.uuidField.bottomAnchor constant:24],
        [keyLabel.leadingAnchor constraintEqualToAnchor:sep.trailingAnchor constant:20],
        [self.keyField.topAnchor constraintEqualToAnchor:keyLabel.bottomAnchor constant:6],
        [self.keyField.leadingAnchor constraintEqualToAnchor:sep.trailingAnchor constant:20],
        [self.keyField.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
        [self.keyField.heightAnchor constraintEqualToConstant:30],

        // 激活按钮
        [activateBtn.topAnchor constraintEqualToAnchor:self.keyField.bottomAnchor constant:10],
        [activateBtn.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],

        // 状态文字
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:activateBtn.centerYAnchor],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:sep.trailingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:activateBtn.leadingAnchor constant:-12],
    ]];

    [self refreshStatus];
}

- (void)refreshStatus {
    License* l = License.shared;
    switch ([l currentState]) {
        case MSLicenseStateActivated:
            self.statusLabel.stringValue = @"✓ 已永久激活";
            self.statusLabel.textColor = [NSColor systemGreenColor];
            break;
        case MSLicenseStateTrialActive: {
            int days = (int)([l trialRemainingSeconds] / 86400);
            int hours = (int)(([l trialRemainingSeconds] - days*86400) / 3600);
            self.statusLabel.stringValue = [NSString stringWithFormat:
                @"试用中，还剩 %d 天 %d 时", days, hours];
            self.statusLabel.textColor = [NSColor secondaryLabelColor];
            break;
        }
        case MSLicenseStateTrialExpired:
            self.statusLabel.stringValue = @"试用已结束，请激活";
            self.statusLabel.textColor = [NSColor systemRedColor];
            break;
    }
}

- (void)showFromWindow:(NSWindow*)parent {
    self.uuidField.stringValue = [License.shared machineUUID];
    [self refreshStatus];
    // 强制还原成初始尺寸，防止上次会话被 macOS 自动 restore 缩小
    NSRect screen = parent ? parent.screen.frame : NSScreen.mainScreen.frame;
    NSRect frame = NSMakeRect(0, 0, 680, 540);
    frame.origin.x = screen.origin.x + (screen.size.width  - frame.size.width)  / 2;
    frame.origin.y = screen.origin.y + (screen.size.height - frame.size.height) / 2;
    [self.window setFrame:frame display:YES];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)copyUUID:(id)sender {
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:self.uuidField.stringValue forType:NSPasteboardTypeString];
    self.statusLabel.stringValue = @"机器码已复制";
    self.statusLabel.textColor = [NSColor systemBlueColor];
}

- (void)activate:(id)sender {
    NSString* k = self.keyField.stringValue;
    MSActivationError err = [License.shared activateWithKey:k];
    switch (err) {
        case MSActivationErrorNone: {
            self.statusLabel.stringValue = @"✓ 激活成功！";
            self.statusLabel.textColor = [NSColor systemGreenColor];
            // 通知主界面刷新
            [NSNotificationCenter.defaultCenter postNotificationName:
                @"MSLicenseDidActivate" object:nil];
            // 1 秒后关窗
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                [self.window close];
            });
            break;
        }
        case MSActivationErrorFormat: {
            self.statusLabel.stringValue = @"激活码格式不对";
            self.statusLabel.textColor = [NSColor systemRedColor];
            break;
        }
        case MSActivationErrorSignature: {
            self.statusLabel.stringValue = @"激活码无效（可能不是给本机的）";
            self.statusLabel.textColor = [NSColor systemRedColor];
            break;
        }
        case MSActivationErrorAlreadyUsed: {
            self.statusLabel.stringValue = @"本激活码已被使用过";
            self.statusLabel.textColor = [NSColor systemRedColor];
            break;
        }
    }
}

@end

// =====================================================================
//                     ActivationOverlayView
// =====================================================================

@interface ActivationOverlayView ()
@property (strong) NSImageView*  qrImageView;
@property (strong) NSTextField*  titleLabel;
@property (strong) NSTextField*  subtitleLabel;
@property (strong) NSButton*     activateBtn;
@end

@implementation ActivationOverlayView

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:0.05 alpha:0.96] CGColor];

        self.titleLabel = [NSTextField labelWithString:@"🔒 试用期已结束"];
        self.titleLabel.font = [NSFont boldSystemFontOfSize:24];
        self.titleLabel.textColor = [NSColor whiteColor];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.titleLabel];

        self.subtitleLabel = [NSTextField wrappingLabelWithString:
            @"3 天免费体验已结束。\n购买永久激活（¥66）后可继续阅读。"];
        self.subtitleLabel.font = [NSFont systemFontOfSize:14];
        self.subtitleLabel.textColor = [NSColor colorWithCalibratedWhite:0.85 alpha:1.0];
        self.subtitleLabel.alignment = NSTextAlignmentCenter;
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.subtitleLabel];

        self.qrImageView = [[NSImageView alloc] init];
        NSString* qrPath = [NSBundle.mainBundle pathForResource:@"wechat_qr" ofType:@"jpg"];
        self.qrImageView.image = [[NSImage alloc] initWithContentsOfFile:qrPath];
        self.qrImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        self.qrImageView.wantsLayer = YES;
        self.qrImageView.layer.cornerRadius = 6;
        self.qrImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.qrImageView];

        NSTextField* qrTip = [NSTextField labelWithString:@"扫码加微信购买"];
        qrTip.font = [NSFont systemFontOfSize:12];
        qrTip.textColor = [NSColor colorWithCalibratedWhite:0.7 alpha:1.0];
        qrTip.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:qrTip];

        self.activateBtn = [NSButton buttonWithTitle:@"立即激活"
                                                target:self
                                                action:@selector(onActivate:)];
        self.activateBtn.bezelStyle = NSBezelStyleRounded;
        self.activateBtn.font = [NSFont boldSystemFontOfSize:14];
        self.activateBtn.translatesAutoresizingMaskIntoConstraints = NO;
        self.activateBtn.controlSize = NSControlSizeLarge;
        [self addSubview:self.activateBtn];

        [NSLayoutConstraint activateConstraints:@[
            [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:60],

            [self.subtitleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:20],
            [self.subtitleLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.8],

            [self.qrImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.qrImageView.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:24],
            [self.qrImageView.widthAnchor constraintEqualToConstant:160],
            [self.qrImageView.heightAnchor constraintEqualToConstant:160],

            [qrTip.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [qrTip.topAnchor constraintEqualToAnchor:self.qrImageView.bottomAnchor constant:6],

            [self.activateBtn.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.activateBtn.topAnchor constraintEqualToAnchor:qrTip.bottomAnchor constant:20],
            [self.activateBtn.widthAnchor constraintEqualToConstant:160],
            [self.activateBtn.heightAnchor constraintEqualToConstant:36],
        ]];
    }
    return self;
}

- (void)onActivate:(id)sender {
    if (self.onActivateTapped) self.onActivateTapped();
}

@end

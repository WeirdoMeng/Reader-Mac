// Central registry of customizable keyboard shortcuts.
// All menu items + the global hotkey ask this object for their current key.
// Changes are persisted in NSUserDefaults and broadcast via NSNotification.

#pragma once
#import <AppKit/AppKit.h>

// Posted whenever any binding changes; observers (AppDelegate, GlobalHotkey)
// rebuild their key paths.
extern NSNotificationName const KeyBindingsDidChangeNotification;

// One assignable action.
@interface KBShortcut : NSObject <NSCopying>
@property (copy)   NSString*            keyChar;    // e.g. "o", "[", "f"
@property (assign) NSEventModifierFlags modifiers;  // any combination
+ (instancetype)keyChar:(NSString*)k modifiers:(NSEventModifierFlags)m;
- (NSString*)displayString;  // e.g. "⌘⌥H"
@end

@interface KBAction : NSObject
@property (copy)   NSString*   actionId;    // stable key for UserDefaults
@property (copy)   NSString*   displayName; // Chinese label
@property (strong) KBShortcut* defaultShortcut;
@property (strong) KBShortcut* shortcut;    // current
@end

@interface KeyBindings : NSObject

+ (instancetype)shared;

- (NSArray<KBAction*>*)allActions;
- (KBAction*)actionWithId:(NSString*)actionId;
- (void)setShortcut:(KBShortcut*)shortcut forActionId:(NSString*)actionId;
- (void)resetActionToDefault:(NSString*)actionId;
- (void)resetAllToDefault;

// ---- 暂存 / 提交模式 ----
// KeyRecorder 录入后只调 setPendingShortcut（不发通知不改 actions），
// 等用户点"保存"再 commitPending（写 UserDefaults + 发通知）。
- (void)setPendingShortcut:(KBShortcut*)s forActionId:(NSString*)actionId;
- (KBShortcut*)effectiveShortcutForActionId:(NSString*)actionId;  // pending 优先
- (BOOL)hasPendingChanges;
- (void)commitPending;
- (void)discardPending;

@end

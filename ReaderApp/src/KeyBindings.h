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

@end

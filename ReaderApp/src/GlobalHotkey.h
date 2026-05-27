// Global Option+H hotkey: toggle app hidden state, matching the Windows
// Reader's Alt+H behavior. Uses Carbon RegisterEventHotKey — does NOT need
// Accessibility / Input-Monitoring permissions.

#pragma once
#import <Foundation/Foundation.h>

@interface GlobalHotkey : NSObject

// Register the hotkey. `block` is invoked on the main thread when fired.
+ (BOOL)registerHotkeyWithBlock:(void (^)(void))block;
+ (void)unregister;

@end

// Global Option+H hotkey: toggle app hidden state, matching the Windows
// Reader's Alt+H behavior. Uses Carbon RegisterEventHotKey — does NOT need
// Accessibility / Input-Monitoring permissions.

#pragma once
#import <Foundation/Foundation.h>

@interface GlobalHotkey : NSObject

// Register the hotkey to (keyChar, modifiers) where modifiers uses
// NSEventModifierFlag* bitmask. Block fires on the main thread.
+ (BOOL)registerWithKeyChar:(NSString*)keyChar
                  modifiers:(NSUInteger)modifiers
                      block:(void (^)(void))block;
+ (void)unregister;

@end

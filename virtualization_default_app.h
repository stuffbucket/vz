//
//  virtualization_default_app.h
//
//  Default GUI implementation for VM graphics applications.
//  This provides a complete, batteries-included window with toolbar,
//  zoom functionality, and standard macOS app behaviors.
//
//  Custom WindowHandler users can ignore this - they receive just the
//  VZVirtualMachineView and build their own window management.
//
//  Created by codehex.
//

#pragma once

#import "virtualization_view.h"

// Application lifecycle - call once per process
void initializeApplication(void);
void runApplication(void);

// Low-level: create raw VZVirtualMachineView for custom handlers
// Consumer is responsible for window management, embedding, etc.
void *createVirtualMachineView(void *machine);

// High-level: create window with full VMWindowController (default GUI)
// Non-blocking, shows window immediately
void *createVirtualMachineWindow(void *machine, void *queue, double width, double height, const char *title, bool enableController, bool confirmStopOnClose);

// Legacy combined API (calls create + run internally)
void startVirtualMachineWindow(void *machine, void *queue, double width, double height, const char *title, bool enableController, bool confirmStopOnClose);

@interface AboutViewController : NSViewController
- (instancetype)init;
@end

@interface AboutPanel : NSPanel
- (instancetype)init;
@end

// VMWindowController manages a single VM's window and view.
// Multiple instances can exist for multi-VM support.
//
// Features:
// - Toolbar with pause/resume/stop controls
// - Input capture toggle
// - Zoom mode with edge scrolling and pinch-to-zoom
// - Pause overlay visual effect
// - Close confirmation dialog (optional)
// - Auto-sizing based on VM graphics resolution
API_AVAILABLE(macos(12.0))
@interface VMWindowController : NSObject <NSWindowDelegate, VZVirtualMachineDelegate, NSToolbarDelegate>
- (instancetype)initWithVirtualMachine:(VZVirtualMachine *)virtualMachine
                                 queue:(dispatch_queue_t)queue
                           windowWidth:(CGFloat)windowWidth
                          windowHeight:(CGFloat)windowHeight
                           windowTitle:(NSString *)windowTitle
                      enableController:(BOOL)enableController
                    confirmStopOnClose:(BOOL)confirmStopOnClose;
- (void)setupAndShowWindow;
- (NSWindow *)window;
@end

// AppDelegate manages application lifecycle and menus.
// Provides standard macOS app menu (About, Hide, Quit) and Window menu.
API_AVAILABLE(macos(12.0))
@interface AppDelegate : NSObject <NSApplicationDelegate>
+ (instancetype)sharedDelegate;
- (void)addWindowController:(VMWindowController *)controller;
- (void)removeWindowController:(VMWindowController *)controller;
@end

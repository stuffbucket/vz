//
//  virtualization_default_app.m
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

#import "virtualization_default_app.h"
#import "virtualization_11.h"

#pragma mark - Application Lifecycle

void initializeApplication()
{
    // Create the shared app instance. Idempotent.
    [VZApplication sharedApplication];

    if (@available(macOS 12, *)) {
        // Set up app delegate if not already done
        if (NSApp.delegate == nil) {
            AppDelegate *appDelegate = [[[AppDelegate alloc] init] autorelease];
            NSApp.delegate = appDelegate;
        }
    }
}

void runApplication()
{
    initializeApplication();
    if (@available(macOS 12, *)) {
        // Safe to call multiple times - no-op if already running
        if (![NSApp isRunning]) {
            [NSApp run];
        }
    }
}

#pragma mark - Low-level View Creation (for custom handlers)

void *createVirtualMachineView(void *machine)
{
    if (@available(macOS 12, *)) {
        @autoreleasepool {
            VZVirtualMachineView *view = [[VZVirtualMachineView alloc] init];
            view.capturesSystemKeys = YES;
            view.virtualMachine = (VZVirtualMachine *)machine;
#ifdef INCLUDE_TARGET_OSX_14
            if (@available(macOS 14.0, *)) {
                view.automaticallyReconfiguresDisplay = YES;
            }
#endif
            return view;
        }
    }
    return NULL;
}

#pragma mark - Per-VM Window Management (default GUI)

void *createVirtualMachineWindow(void *machine, void *queue, double width, double height, const char *title, bool enableController, bool confirmStopOnClose)
{
    initializeApplication();

    if (@available(macOS 12, *)) {
        __block VMWindowController *controller = nil;

        void (^createWindow)(void) = ^{
            @autoreleasepool {
                NSString *windowTitle = [NSString stringWithUTF8String:title];
                controller = [[VMWindowController alloc]
                    initWithVirtualMachine:(VZVirtualMachine *)machine
                                     queue:(dispatch_queue_t)queue
                               windowWidth:(CGFloat)width
                              windowHeight:(CGFloat)height
                               windowTitle:windowTitle
                          enableController:enableController
                        confirmStopOnClose:confirmStopOnClose];

                // Register with app delegate and show window
                AppDelegate *appDelegate = (AppDelegate *)NSApp.delegate;
                if (appDelegate) {
                    [appDelegate addWindowController:controller];
                }
                [controller setupAndShowWindow];
            }
        };

        // UI operations must happen on main thread
        if ([NSThread isMainThread]) {
            createWindow();
        } else {
            dispatch_sync(dispatch_get_main_queue(), createWindow);
        }

        return controller;
    }
    return NULL;
}

#pragma mark - Legacy API (backward compatibility)

// Legacy: global window controller for single-VM case
static VMWindowController *_legacyWindowController API_AVAILABLE(macos(12.0)) = nil;

void startVirtualMachineWindow(void *machine, void *queue, double width, double height, const char *title, bool enableController, bool confirmStopOnClose)
{
    if (@available(macOS 12, *)) {
        void *controller = createVirtualMachineWindow(machine, queue, width, height, title, enableController, confirmStopOnClose);
        if (controller) {
            _legacyWindowController = (VMWindowController *)controller;
            // Window already shown by createVirtualMachineWindow
            runApplication();
        }
    }
}

#pragma mark - About Panel

@implementation AboutViewController

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    return self;
}

- (void)loadView
{
    self.view = [NSView new];
    NSImageView *imageView = [NSImageView imageViewWithImage:[NSApp applicationIconImage]];
    NSTextField *appLabel = [self makeLabel:[[NSProcessInfo processInfo] processName]];
    [appLabel setFont:[NSFont boldSystemFontOfSize:16]];
    NSTextField *subLabel = [self makePoweredByLabel];

    NSStackView *stackView = [NSStackView stackViewWithViews:@[
        imageView,
        appLabel,
        subLabel,
    ]];
    [stackView setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [stackView setDistribution:NSStackViewDistributionFillProportionally];
    [stackView setSpacing:10];
    [stackView setAlignment:NSLayoutAttributeCenterX];
    [stackView setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [stackView setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];

    [self.view addSubview:stackView];

    [NSLayoutConstraint activateConstraints:@[
        [imageView.widthAnchor constraintEqualToConstant:80],
        [imageView.heightAnchor constraintEqualToConstant:80],
        [stackView.topAnchor constraintEqualToAnchor:self.view.topAnchor
                                            constant:4],
        [stackView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor
                                               constant:-16],
        [stackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                                constant:32],
        [stackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                                 constant:-32],
        [stackView.widthAnchor constraintEqualToConstant:300]
    ]];
}

- (NSTextField *)makePoweredByLabel
{
    NSMutableAttributedString *poweredByAttr = [[[NSMutableAttributedString alloc]
        initWithString:@"Powered by "
            attributes:@{
                NSForegroundColorAttributeName : [NSColor labelColor]
            }] autorelease];
    NSURL *repositoryURL = [NSURL URLWithString:@"https://github.com/Code-Hex/vz"];
    NSMutableAttributedString *repository = [self makeHyperLink:@"github.com/Code-Hex/vz" withURL:repositoryURL];
    [poweredByAttr appendAttributedString:repository];
    [poweredByAttr addAttribute:NSFontAttributeName
                          value:[NSFont systemFontOfSize:12]
                          range:NSMakeRange(0, [poweredByAttr length])];

    NSTextField *label = [self makeLabel:@""];
    [label setSelectable:YES];
    [label setAllowsEditingTextAttributes:YES];
    [label setAttributedStringValue:poweredByAttr];
    return label;
}

- (NSTextField *)makeLabel:(NSString *)label
{
    NSTextField *appLabel = [NSTextField labelWithString:label];
    [appLabel setTextColor:[NSColor labelColor]];
    [appLabel setEditable:NO];
    [appLabel setSelectable:NO];
    [appLabel setBezeled:NO];
    [appLabel setBordered:NO];
    [appLabel setBackgroundColor:[NSColor clearColor]];
    [appLabel setAlignment:NSTextAlignmentCenter];
    [appLabel setLineBreakMode:NSLineBreakByWordWrapping];
    [appLabel setUsesSingleLineMode:NO];
    [appLabel setMaximumNumberOfLines:20];
    return appLabel;
}

// https://developer.apple.com/library/archive/qa/qa1487/_index.html
- (NSMutableAttributedString *)makeHyperLink:(NSString *)inString withURL:(NSURL *)aURL
{
    NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] initWithString:inString];
    NSRange range = NSMakeRange(0, [attrString length]);

    [attrString beginEditing];
    [attrString addAttribute:NSLinkAttributeName value:[aURL absoluteString] range:range];
    [attrString addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] range:range];
    [attrString addAttribute:NSUnderlineStyleAttributeName
                       value:[NSNumber numberWithInt:NSUnderlineStyleSingle]
                       range:range];
    [attrString endEditing];
    return [attrString autorelease];
}

@end

@implementation AboutPanel

- (instancetype)init
{
    self = [super initWithContentRect:NSZeroRect
                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                              backing:NSBackingStoreBuffered
                                defer:NO];

    AboutViewController *viewController = [[[AboutViewController alloc] init] autorelease];
    [self setContentViewController:viewController];
    [self setTitleVisibility:NSWindowTitleHidden];
    [self setTitlebarAppearsTransparent:YES];
    [self setBecomesKeyOnlyIfNeeded:NO];
    [self center];
    return self;
}

@end

#pragma mark - VMWindowController

@implementation VMWindowController {
    VZVirtualMachine *_virtualMachine;
    dispatch_queue_t _queue;
    VZVirtualMachineView *_virtualMachineView;
    NSWindow *_window;
    NSToolbar *_toolbar;
    BOOL _enableController;
    NSVisualEffectView *_pauseOverlayView;
    BOOL _isZoomEnabled;
    NSTimer *_scrollTimer;
    NSPoint _scrollDelta;
    id _mouseMovedMonitor;
    id _scrollWheelMonitor;
    BOOL _confirmStopOnClose;
    NSButton *_pauseResumeButton;
}

- (instancetype)initWithVirtualMachine:(VZVirtualMachine *)virtualMachine
                                 queue:(dispatch_queue_t)queue
                           windowWidth:(CGFloat)windowWidth
                          windowHeight:(CGFloat)windowHeight
                           windowTitle:(NSString *)windowTitle
                      enableController:(BOOL)enableController
                    confirmStopOnClose:(BOOL)confirmStopOnClose
{
    self = [super init];
    _virtualMachine = virtualMachine;
    [_virtualMachine setDelegate:self];
    _confirmStopOnClose = confirmStopOnClose;

    // Setup virtual machine view
    VZVirtualMachineView *view = [[[VZVirtualMachineView alloc] init] autorelease];
    view.capturesSystemKeys = YES;
    view.virtualMachine = _virtualMachine;
#ifdef INCLUDE_TARGET_OSX_14
    if (@available(macOS 14.0, *)) {
        view.automaticallyReconfiguresDisplay = YES;
    }
#endif
    _virtualMachineView = view;
    _queue = queue;

    // Setup window
    _window = [self createMainWindowWithTitle:windowTitle width:windowWidth height:windowHeight];
    _toolbar = [self createCustomToolbar];
    _enableController = enableController;
    [_virtualMachine addObserver:self
                      forKeyPath:@"state"
                         options:NSKeyValueObservingOptionNew
                         context:nil];
    _pauseOverlayView = [self createPauseOverlayEffectView:_virtualMachineView];
    [_virtualMachineView addSubview:_pauseOverlayView];
    _isZoomEnabled = NO;
    return self;
}

- (void)dealloc
{
    if (_mouseMovedMonitor) {
        [NSEvent removeMonitor:_mouseMovedMonitor];
        _mouseMovedMonitor = nil;
    }
    if (_scrollWheelMonitor) {
        [NSEvent removeMonitor:_scrollWheelMonitor];
        _scrollWheelMonitor = nil;
    }
    [self stopScrollTimer];
    if (_virtualMachine) {
        [_virtualMachine removeObserver:self forKeyPath:@"state"];
    }
    _virtualMachineView = nil;
    _virtualMachine = nil;
    _queue = nil;
    _toolbar = nil;
    _window = nil;
    _pauseOverlayView = nil;
    [super dealloc];
}

#pragma mark - VM State Queries

- (BOOL)canStopVirtualMachine
{
    __block BOOL result;
    dispatch_sync(_queue, ^{ result = _virtualMachine.canStop; });
    return result;
}

- (BOOL)canResumeVirtualMachine
{
    __block BOOL result;
    dispatch_sync(_queue, ^{ result = _virtualMachine.canResume; });
    return result;
}

- (BOOL)canPauseVirtualMachine
{
    __block BOOL result;
    dispatch_sync(_queue, ^{ result = _virtualMachine.canPause; });
    return result;
}

- (BOOL)canStartVirtualMachine
{
    __block BOOL result;
    dispatch_sync(_queue, ^{ result = _virtualMachine.canStart; });
    return result;
}

#pragma mark - KVO State Observer

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if ([keyPath isEqualToString:@"state"]) {
        VZVirtualMachineState newState = (VZVirtualMachineState)[change[NSKeyValueChangeNewKey] integerValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updatePauseResumeButton];
            if (newState == VZVirtualMachineStatePaused) {
                [self showOverlay];
            } else {
                [self hideOverlay];
            }
            if (newState == VZVirtualMachineStateStopped) {
                [_window close];
            }
        });
    }
}

#pragma mark - Pause Overlay

- (NSVisualEffectView *)createPauseOverlayEffectView:(NSView *)view
{
    NSVisualEffectView *effectView = [[[NSVisualEffectView alloc] initWithFrame:view.bounds] autorelease];
    effectView.wantsLayer = YES;
    effectView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    effectView.state = NSVisualEffectStateActive;
    effectView.alphaValue = 0.7;
    effectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    effectView.hidden = YES;
    return effectView;
}

- (void)showOverlay
{
    if (_pauseOverlayView)
        _pauseOverlayView.hidden = NO;
}

- (void)hideOverlay
{
    if (_pauseOverlayView)
        _pauseOverlayView.hidden = YES;
}

#pragma mark - Toolbar

static NSString *const CaptureInputToolbarIdentifier = @"CaptureInput";
static NSString *const ZoomToolbarIdentifier = @"Zoom";
static NSString *const PauseResumeToolbarIdentifier = @"PauseResume";
static NSString *const PowerToolbarIdentifier = @"Power";

- (NSArray<NSToolbarItemIdentifier> *)setupToolbarItemIdentifiers
{
    NSMutableArray<NSToolbarItemIdentifier> *toolbarItems = [NSMutableArray array];
    if (_enableController) {
        [toolbarItems addObject:CaptureInputToolbarIdentifier];
        [toolbarItems addObject:PauseResumeToolbarIdentifier];
        [toolbarItems addObject:PowerToolbarIdentifier];
    }
    [toolbarItems addObject:NSToolbarFlexibleSpaceItemIdentifier];
    [toolbarItems addObject:ZoomToolbarIdentifier];
    return [toolbarItems copy];
}

- (NSToolbar *)createCustomToolbar
{
    NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier:@"CustomToolbar"] autorelease];
    [toolbar setDelegate:self];
    [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
    [toolbar setShowsBaselineSeparator:NO];
    [toolbar setAllowsUserCustomization:NO];
    [toolbar setAutosavesConfiguration:NO];
    return toolbar;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return [self setupToolbarItemIdentifiers];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return @[
        CaptureInputToolbarIdentifier, ZoomToolbarIdentifier, PauseResumeToolbarIdentifier,
        PowerToolbarIdentifier, NSToolbarFlexibleSpaceItemIdentifier
    ];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
        itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
    willBeInsertedIntoToolbar:(BOOL)flag
{
    NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];

    if ([itemIdentifier isEqualToString:CaptureInputToolbarIdentifier]) {
        NSButton *captureButton = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 40, 40)] autorelease];
        captureButton.bezelStyle = NSBezelStyleTexturedRounded;
        BOOL isCapturing = _virtualMachineView.capturesSystemKeys;
        NSString *iconName = isCapturing ? @"keyboard.fill" : @"keyboard";
        [captureButton setImage:[NSImage imageWithSystemSymbolName:iconName accessibilityDescription:nil]];
        [captureButton setTarget:self];
        [captureButton setAction:@selector(toggleCaptureInput:)];
        [captureButton setButtonType:NSButtonTypeToggle];
        [captureButton setState:isCapturing ? NSControlStateValueOn : NSControlStateValueOff];
        [item setView:captureButton];
        [item setLabel:@"Capture"];
        [item setToolTip:@"Toggle Input Capture"];
    } else if ([itemIdentifier isEqualToString:PauseResumeToolbarIdentifier]) {
        NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 40, 40)] autorelease];
        button.bezelStyle = NSBezelStyleTexturedRounded;
        [button setTarget:self];
        [button setAction:@selector(pauseResumeButtonClicked:)];
        [button setButtonType:NSButtonTypeMomentaryPushIn];
        _pauseResumeButton = button;
        [self updatePauseResumeButton];
        [item setView:button];
        [item setLabel:@"Pause/Resume"];
    } else if ([itemIdentifier isEqualToString:PowerToolbarIdentifier]) {
        [item setImage:[NSImage imageWithSystemSymbolName:@"power" accessibilityDescription:nil]];
        [item setLabel:@"Power"];
        [item setTarget:self];
        [item setToolTip:@"Power ON/OFF"];
        [item setBordered:YES];
        [item setAction:@selector(powerButtonClicked:)];
    } else if ([itemIdentifier isEqualToString:ZoomToolbarIdentifier]) {
        NSButton *zoomButton = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 40, 40)] autorelease];
        zoomButton.bezelStyle = NSBezelStyleTexturedRounded;
        [zoomButton setImage:[NSImage imageWithSystemSymbolName:@"plus.magnifyingglass" accessibilityDescription:nil]];
        [zoomButton setTarget:self];
        [zoomButton setAction:@selector(toggleZoomMode:)];
        [zoomButton setButtonType:NSButtonTypeToggle];
        [item setView:zoomButton];
        [item setLabel:@"Zoom"];
        [item setToolTip:@"Toggle Zoom"];
    }

    return item;
}

#pragma mark - Button Actions

- (void)toggleCaptureInput:(id)sender
{
    NSButton *button = (NSButton *)sender;
    BOOL isCapturing = (button.state == NSControlStateValueOn);
    _virtualMachineView.capturesSystemKeys = isCapturing;
    NSString *iconName = isCapturing ? @"keyboard.fill" : @"keyboard";
    [button setImage:[NSImage imageWithSystemSymbolName:iconName accessibilityDescription:nil]];
}

- (void)updatePauseResumeButton
{
    if (!_pauseResumeButton)
        return;

    BOOL canPause = [self canPauseVirtualMachine];
    BOOL canResume = [self canResumeVirtualMachine];

    if (canPause) {
        [_pauseResumeButton setImage:[NSImage imageWithSystemSymbolName:@"pause.fill" accessibilityDescription:nil]];
        [_pauseResumeButton setToolTip:@"Pause"];
        [_pauseResumeButton setEnabled:YES];
    } else if (canResume) {
        [_pauseResumeButton setImage:[NSImage imageWithSystemSymbolName:@"play.fill" accessibilityDescription:nil]];
        [_pauseResumeButton setToolTip:@"Resume"];
        [_pauseResumeButton setEnabled:YES];
    } else {
        [_pauseResumeButton setImage:[NSImage imageWithSystemSymbolName:@"pause.fill" accessibilityDescription:nil]];
        [_pauseResumeButton setToolTip:@"Pause/Resume"];
        [_pauseResumeButton setEnabled:NO];
    }
}

- (void)pauseResumeButtonClicked:(id)sender
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self canPauseVirtualMachine]) {
            dispatch_sync(_queue, ^{
                [_virtualMachine pauseWithCompletionHandler:^(NSError *err) {
                    if (err)
                        [self showErrorAlertWithMessage:@"Failed to pause Virtual Machine" error:err];
                }];
            });
        } else if ([self canResumeVirtualMachine]) {
            dispatch_sync(_queue, ^{
                [_virtualMachine resumeWithCompletionHandler:^(NSError *err) {
                    if (err)
                        [self showErrorAlertWithMessage:@"Failed to resume Virtual Machine" error:err];
                }];
            });
        }
    });
}

- (void)powerButtonClicked:(id)sender
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self canStartVirtualMachine]) {
            dispatch_sync(_queue, ^{
                [_virtualMachine startWithCompletionHandler:^(NSError *err) {
                    if (err)
                        [self showErrorAlertWithMessage:@"Failed to start Virtual Machine" error:err];
                }];
            });
            return;
        }
        if ([self canStopVirtualMachine]) {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setIcon:[NSImage imageNamed:NSImageNameCaution]];
            [alert setMessageText:@"Force Stop Warning"];
            [alert setInformativeText:@"This action will stop the VM without a clean shutdown, similar to unplugging a PC.\n\nDo you want to force stop?"];
            [alert setAlertStyle:NSAlertStyleWarning];
            [alert addButtonWithTitle:@"Stop"];
            [alert addButtonWithTitle:@"Cancel"];

            NSModalResponse response = [alert runModal];
            if (response != NSAlertFirstButtonReturn)
                return;

            dispatch_sync(_queue, ^{
                [_virtualMachine stopWithCompletionHandler:^(NSError *err) {
                    if (err)
                        [self showErrorAlertWithMessage:@"Failed to stop Virtual Machine" error:err];
                }];
            });
        }
    });
}

- (void)showErrorAlertWithMessage:(NSString *)message error:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:message];
        [alert setInformativeText:[NSString stringWithFormat:@"Error: %@\nCode: %ld", [error localizedDescription], (long)[error code]]];
        [alert setAlertStyle:NSAlertStyleCritical];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    });
}

#pragma mark - VZVirtualMachineDelegate

- (void)guestDidStopVirtualMachine:(VZVirtualMachine *)virtualMachine
{
    // Window will close via state observer
}

- (void)virtualMachine:(VZVirtualMachine *)virtualMachine didStopWithError:(NSError *)error
{
    NSLog(@"VM %@ didStopWithError: %@", virtualMachine, error);
}

#pragma mark - Window Setup

- (void)setupAndShowWindow
{
    [self setupGraphicWindow];
}

- (NSWindow *)window
{
    return _window;
}

- (NSWindow *)createMainWindowWithTitle:(NSString *)title width:(CGFloat)width height:(CGFloat)height
{
    NSRect rect = NSMakeRect(0, 0, width, height);
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:rect
                                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO] autorelease];
    [window setTitle:title];
    return window;
}

- (BOOL)windowShouldClose:(NSWindow *)sender
{
    if (!_confirmStopOnClose)
        return YES;

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setIcon:[NSImage imageNamed:NSImageNameCaution]];
    [alert setMessageText:@"Stop Virtual Machine?"];
    [alert setInformativeText:@"Closing this window will also stop the virtual machine. If you want to keep it running, please minimize the window instead."];
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Stop"];
    [alert setAlertStyle:NSAlertStyleCritical];

    NSModalResponse response = [alert runModal];
    return response == NSAlertSecondButtonReturn;
}

- (void)windowWillClose:(NSNotification *)notification
{
    dispatch_sync(_queue, ^{
        if (_virtualMachine.canStop) {
            [_virtualMachine stopWithCompletionHandler:^(NSError *error) {
                if (error)
                    NSLog(@"Error stopping VM on window close: %@", error);
            }];
        }
    });

    // Remove from app delegate - this may trigger app termination
    AppDelegate *appDelegate = (AppDelegate *)NSApp.delegate;
    if (appDelegate) {
        [appDelegate removeWindowController:self];
    }
}

- (void)setupGraphicWindow
{
    [_window setTitlebarAppearsTransparent:YES];
    [_window setToolbar:_toolbar];
    [_window setOpaque:NO];
    [_window center];

    _mouseMovedMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskMouseMoved
                                                               handler:^NSEvent *(NSEvent *event) {
                                                                   [self handleMouseMovement:event];
                                                                   return event;
                                                               }];

    _scrollWheelMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel
                                                                handler:^NSEvent *(NSEvent *event) {
                                                                    [self handleScrollWheel:event];
                                                                    return event;
                                                                }];

    NSScrollView *scrollView = [self createScrollViewForVirtualMachineView:_virtualMachineView];
    [_window setContentView:scrollView];

    [_virtualMachineView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [NSLayoutConstraint activateConstraints:@[
        [_virtualMachineView.leadingAnchor constraintEqualToAnchor:_window.contentView.leadingAnchor],
        [_virtualMachineView.trailingAnchor constraintEqualToAnchor:_window.contentView.trailingAnchor],
        [_virtualMachineView.topAnchor constraintEqualToAnchor:_window.contentView.topAnchor],
        [_virtualMachineView.bottomAnchor constraintEqualToAnchor:_window.contentView.bottomAnchor]
    ]];

    NSSize sizeInPixels = [self getVirtualMachineSizeInPixels];
    if (!NSEqualSizes(sizeInPixels, NSZeroSize)) {
        [_window setContentAspectRatio:sizeInPixels];
        CGFloat windowWidth = _window.frame.size.width;
        CGFloat initialHeight = windowWidth * (sizeInPixels.height / sizeInPixels.width);
        [_window setContentSize:NSMakeSize(windowWidth, initialHeight)];
    }

    [_window setDelegate:self];
    [_window makeKeyAndOrderFront:nil];
    [_window setReleasedWhenClosed:NO];
}

- (NSSize)getVirtualMachineSizeInPixels
{
    __block NSSize sizeInPixels = NSZeroSize;
#ifdef INCLUDE_TARGET_OSX_14
    if (@available(macOS 14.0, *)) {
        dispatch_sync(_queue, ^{
            if (_virtualMachine.graphicsDevices.count > 0) {
                VZGraphicsDevice *graphicsDevice = _virtualMachine.graphicsDevices[0];
                if (graphicsDevice.displays.count > 0) {
                    VZGraphicsDisplay *displayConfig = graphicsDevice.displays[0];
                    sizeInPixels = displayConfig.sizeInPixels;
                }
            }
        });
    }
#endif
    return sizeInPixels;
}

#pragma mark - Zoom Function

- (void)toggleZoomMode:(id)sender
{
    _isZoomEnabled = !_isZoomEnabled;
    NSScrollView *scrollView = (NSScrollView *)_window.contentView;

    if (!_isZoomEnabled) {
        [NSAnimationContext
            runAnimationGroup:^(NSAnimationContext *context) {
                [context setDuration:0.3];
                [[_window.contentView animator] setMagnification:1.0];
            }
            completionHandler:^{
                if ([scrollView isKindOfClass:[NSScrollView class]]) {
                    scrollView.hasVerticalScroller = NO;
                    scrollView.hasHorizontalScroller = NO;
                }
            }];
    } else {
        if ([scrollView isKindOfClass:[NSScrollView class]]) {
            scrollView.hasVerticalScroller = YES;
            scrollView.hasHorizontalScroller = YES;
            scrollView.autohidesScrollers = YES;
        }
    }
}

- (NSScrollView *)createScrollViewForVirtualMachineView:(VZVirtualMachineView *)view
{
    NSScrollView *scrollView = [[[NSScrollView alloc] initWithFrame:_window.contentView.bounds] autorelease];
    scrollView.hasVerticalScroller = NO;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.documentView = view;
    scrollView.allowsMagnification = YES;
    scrollView.maxMagnification = 4.0;
    scrollView.minMagnification = 1.0;

    NSMagnificationGestureRecognizer *magnifyRecognizer =
        [[[NSMagnificationGestureRecognizer alloc] initWithTarget:self action:@selector(handleMagnification:)] autorelease];
    magnifyRecognizer.delaysMagnificationEvents = NO;
    [scrollView addGestureRecognizer:magnifyRecognizer];

    return scrollView;
}

- (void)handleMagnification:(NSMagnificationGestureRecognizer *)recognizer
{
    if (!_isZoomEnabled)
        return;

    NSScrollView *scrollView = (NSScrollView *)recognizer.view;
    CGFloat newMagnification = scrollView.magnification + recognizer.magnification;
    newMagnification = MIN(scrollView.maxMagnification, MAX(scrollView.minMagnification, newMagnification));

    NSPoint locationInView = [recognizer locationInView:scrollView];
    NSPoint centeredPoint = [scrollView.contentView convertPoint:locationInView fromView:scrollView];
    [scrollView setMagnification:newMagnification centeredAtPoint:centeredPoint];
}

- (void)handleScrollWheel:(NSEvent *)event
{
    if (!_isZoomEnabled)
        return;
    if (!(event.modifierFlags & NSEventModifierFlagCommand) && !(event.modifierFlags & NSEventModifierFlagOption))
        return;

    NSScrollView *scrollView = (NSScrollView *)_window.contentView;
    if (![scrollView isKindOfClass:[NSScrollView class]])
        return;

    CGFloat zoomDelta = event.scrollingDeltaY * 0.01;
    CGFloat newMagnification = scrollView.magnification + zoomDelta;
    newMagnification = MIN(scrollView.maxMagnification, MAX(scrollView.minMagnification, newMagnification));

    NSPoint mouseLocation = [_window.contentView convertPoint:event.locationInWindow fromView:nil];
    NSPoint centeredPoint = [scrollView.contentView convertPoint:mouseLocation fromView:_window.contentView];
    [scrollView setMagnification:newMagnification centeredAtPoint:centeredPoint];
}

- (void)handleMouseMovement:(NSEvent *)event
{
    if (!_isZoomEnabled) {
        [self stopScrollTimer];
        return;
    }

    NSScrollView *scrollView = (NSScrollView *)_window.contentView;
    if (![scrollView isKindOfClass:[NSScrollView class]]) {
        [self stopScrollTimer];
        return;
    }

    NSPoint mouseLocation = [scrollView.window convertPointToScreen:event.locationInWindow];
    NSRect windowFrame = scrollView.window.frame;

    const CGFloat margin = 24.0;
    const CGFloat baseScrollSpeed = 5.0;
    _scrollDelta = NSMakePoint(0, 0);

    if (mouseLocation.x < NSMinX(windowFrame) + margin) {
        _scrollDelta.x = -baseScrollSpeed;
    } else if (mouseLocation.x > NSMaxX(windowFrame) - margin) {
        _scrollDelta.x = baseScrollSpeed;
    }

    CGFloat titleBarHeight = scrollView.window.frame.size.height - scrollView.window.contentView.frame.size.height;
    if (mouseLocation.y >= (NSMaxY(windowFrame) - titleBarHeight)) {
        _scrollDelta.y = 0;
    } else if (mouseLocation.y < NSMinY(windowFrame) + margin) {
        _scrollDelta.y = -baseScrollSpeed;
    } else if (mouseLocation.y > NSMaxY(windowFrame) - margin - titleBarHeight) {
        _scrollDelta.y = baseScrollSpeed;
    }

    if (_scrollDelta.x != 0 || _scrollDelta.y != 0) {
        [self startScrollTimer];
    } else {
        [self stopScrollTimer];
    }
}

- (void)startScrollTimer
{
    if (_scrollTimer == nil) {
        _scrollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                        target:self
                                                      selector:@selector(scrollTick:)
                                                      userInfo:nil
                                                       repeats:YES];
    }
}

- (void)stopScrollTimer
{
    [_scrollTimer invalidate];
    _scrollTimer = nil;
}

- (void)scrollTick:(NSTimer *)timer
{
    NSScrollView *scrollView = (NSScrollView *)_window.contentView;
    if (![scrollView isKindOfClass:[NSScrollView class]]) {
        [self stopScrollTimer];
        return;
    }

    NSClipView *clipView = scrollView.contentView;
    NSPoint currentOrigin = clipView.bounds.origin;
    currentOrigin.x += _scrollDelta.x;
    currentOrigin.y += _scrollDelta.y;
    currentOrigin.x = MAX(0, MIN(currentOrigin.x, clipView.documentView.frame.size.width - clipView.bounds.size.width));
    currentOrigin.y = MAX(0, MIN(currentOrigin.y, clipView.documentView.frame.size.height - clipView.bounds.size.height));
    [clipView setBoundsOrigin:currentOrigin];
}

@end

#pragma mark - AppDelegate

@implementation AppDelegate {
    NSMutableArray<VMWindowController *> *_windowControllers;
}

static AppDelegate *_sharedDelegate API_AVAILABLE(macos(12.0)) = nil;

+ (instancetype)sharedDelegate
{
    return _sharedDelegate;
}

- (instancetype)init
{
    self = [super init];
    _windowControllers = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc
{
    [_windowControllers release];
    [super dealloc];
}

- (void)addWindowController:(VMWindowController *)controller
{
    @synchronized(_windowControllers) {
        [_windowControllers addObject:controller];
    }
}

- (void)removeWindowController:(VMWindowController *)controller
{
    BOOL shouldTerminate = NO;
    @synchronized(_windowControllers) {
        [_windowControllers removeObject:controller];
        shouldTerminate = (_windowControllers.count == 0);
    }
    if (shouldTerminate) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp terminate:nil];
        });
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    _sharedDelegate = self;
    [self setupMenuBar];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    // We handle termination manually in removeWindowController
    // to properly track VM windows vs other windows
    return NO;
}

#pragma mark - Menu Bar

- (void)setupMenuBar
{
    NSMenu *menuBar = [[[NSMenu alloc] init] autorelease];
    NSMenuItem *menuBarItem = [[[NSMenuItem alloc] init] autorelease];
    [menuBar addItem:menuBarItem];
    [NSApp setMainMenu:menuBar];

    NSMenu *appMenu = [self setupApplicationMenu];
    [menuBarItem setSubmenu:appMenu];

    NSMenu *windowMenu = [self setupWindowMenu];
    NSMenuItem *windowMenuItem = [[[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""] autorelease];
    [menuBar addItem:windowMenuItem];
    [windowMenuItem setSubmenu:windowMenu];

    NSMenu *helpMenu = [self setupHelpMenu];
    NSMenuItem *helpMenuItem = [[[NSMenuItem alloc] initWithTitle:@"Help" action:nil keyEquivalent:@""] autorelease];
    [menuBar addItem:helpMenuItem];
    [helpMenuItem setSubmenu:helpMenu];
}

- (NSMenu *)setupApplicationMenu
{
    NSMenu *appMenu = [[[NSMenu alloc] init] autorelease];
    NSString *applicationName = [[NSProcessInfo processInfo] processName];

    NSMenuItem *aboutMenuItem = [[[NSMenuItem alloc]
        initWithTitle:[NSString stringWithFormat:@"About %@", applicationName]
               action:@selector(openAboutWindow:)
        keyEquivalent:@""] autorelease];

    NSMenuItem *servicesMenuItem = [[[NSMenuItem alloc] initWithTitle:@"Services" action:nil keyEquivalent:@""] autorelease];
    NSMenu *servicesMenu = [[[NSMenu alloc] initWithTitle:@"Services"] autorelease];
    [servicesMenuItem setSubmenu:servicesMenu];
    [NSApp setServicesMenu:servicesMenu];

    NSMenuItem *hideOthersItem = [[[NSMenuItem alloc]
        initWithTitle:@"Hide Others"
               action:@selector(hideOtherApplications:)
        keyEquivalent:@"h"] autorelease];
    [hideOthersItem setKeyEquivalentModifierMask:(NSEventModifierFlagOption | NSEventModifierFlagCommand)];

    NSArray *menuItems = @[
        aboutMenuItem,
        [NSMenuItem separatorItem],
        servicesMenuItem,
        [NSMenuItem separatorItem],
        [[[NSMenuItem alloc] initWithTitle:[@"Hide " stringByAppendingString:applicationName]
                                    action:@selector(hide:)
                             keyEquivalent:@"h"] autorelease],
        hideOthersItem,
        [NSMenuItem separatorItem],
        [[[NSMenuItem alloc] initWithTitle:[@"Quit " stringByAppendingString:applicationName]
                                    action:@selector(terminate:)
                             keyEquivalent:@"q"] autorelease],
    ];
    for (NSMenuItem *menuItem in menuItems) {
        [appMenu addItem:menuItem];
    }
    return appMenu;
}

- (NSMenu *)setupWindowMenu
{
    NSMenu *windowMenu = [[[NSMenu alloc] initWithTitle:@"Window"] autorelease];
    NSArray *menuItems = @[
        [[[NSMenuItem alloc] initWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"] autorelease],
        [[[NSMenuItem alloc] initWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""] autorelease],
        [NSMenuItem separatorItem],
        [[[NSMenuItem alloc] initWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""] autorelease],
    ];
    for (NSMenuItem *menuItem in menuItems) {
        [windowMenu addItem:menuItem];
    }
    [NSApp setWindowsMenu:windowMenu];
    return windowMenu;
}

- (NSMenu *)setupHelpMenu
{
    NSMenu *helpMenu = [[[NSMenu alloc] initWithTitle:@"Help"] autorelease];
    [helpMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Report issue"
                                                  action:@selector(reportIssue:)
                                           keyEquivalent:@""] autorelease]];
    [NSApp setHelpMenu:helpMenu];
    return helpMenu;
}

- (void)reportIssue:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/Code-Hex/vz/issues/new"]];
}

- (void)openAboutWindow:(id)sender
{
    AboutPanel *aboutPanel = [[[AboutPanel alloc] init] autorelease];
    [aboutPanel makeKeyAndOrderFront:nil];
}

@end

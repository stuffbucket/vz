//
//  app_menu.m
//
//  App-specific File menu for gui-linux VM management.
//

#import <Cocoa/Cocoa.h>

// Go exports for VM management
extern void newVMFromURLGoCallback(const char *url, const char *vmName);
extern void startVMGoCallback(const char *vmName, const char *isoPath);
extern char *getVMListCallback(void);
extern int isVMRunningCallback(const char *vmName);

@interface FileMenuHandler : NSObject
+ (instancetype)sharedHandler;
- (void)setupFileMenu;
- (void)startExistingVM:(id)sender;
- (void)newVMFromURL:(id)sender;
@end

@implementation FileMenuHandler

static FileMenuHandler *_sharedHandler = nil;

+ (instancetype)sharedHandler
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedHandler = [[FileMenuHandler alloc] init];
    });
    return _sharedHandler;
}

- (void)setupFileMenu
{
    NSMenu *mainMenu = [NSApp mainMenu];
    if (!mainMenu) return;
    
    // Create File menu
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    
    NSMenuItem *startVMItem = [[NSMenuItem alloc]
        initWithTitle:@"Start VM…"
               action:@selector(startExistingVM:)
        keyEquivalent:@"o"];
    [startVMItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [startVMItem setTarget:self];
    [fileMenu addItem:startVMItem];
    
    NSMenuItem *newVMItem = [[NSMenuItem alloc]
        initWithTitle:@"Create New VM…"
               action:@selector(newVMFromURL:)
        keyEquivalent:@"n"];
    [newVMItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagShift)];
    [newVMItem setTarget:self];
    [fileMenu addItem:newVMItem];
    
    // Insert File menu after the app menu (index 1)
    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    [fileMenuItem setSubmenu:fileMenu];
    [mainMenu insertItem:fileMenuItem atIndex:1];
}

- (void)startExistingVM:(id)sender
{
    // Get VM list from Go
    char *vmListCStr = getVMListCallback();
    NSString *vmListStr = [NSString stringWithUTF8String:vmListCStr];
    free(vmListCStr);
    
    if (vmListStr.length == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"No VMs Available"];
        [alert setInformativeText:@"No virtual machines have been created yet. Use 'Create New VM…' to create one."];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }
    
    NSArray *vmNames = [vmListStr componentsSeparatedByString:@"\n"];
    
    // Build the alert with popup button
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Start Virtual Machine"];
    [alert setInformativeText:@"Select a VM to start:"];
    [alert addButtonWithTitle:@"Start"];
    [alert addButtonWithTitle:@"Cancel"];
    
    // Create container for popup and optional ISO field
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 60)];
    
    // VM selector popup
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 34, 300, 24) pullsDown:NO];
    for (NSString *vmName in vmNames) {
        [popup addItemWithTitle:vmName];
        // Gray out running VMs
        if (isVMRunningCallback([vmName UTF8String])) {
            NSMenuItem *item = [popup lastItem];
            [item setEnabled:NO];
            [item setTitle:[NSString stringWithFormat:@"%@ (running)", vmName]];
        }
    }
    [container addSubview:popup];
    
    // Optional ISO field
    NSTextField *isoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 6, 40, 20)];
    [isoLabel setStringValue:@"ISO:"];
    [isoLabel setBezeled:NO];
    [isoLabel setDrawsBackground:NO];
    [isoLabel setEditable:NO];
    [isoLabel setSelectable:NO];
    [container addSubview:isoLabel];
    
    NSTextField *isoInput = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 4, 260, 24)];
    [isoInput setStringValue:@""];
    [isoInput setPlaceholderString:@"(optional) /path/to/boot.iso"];
    [container addSubview:isoInput];
    
    [alert setAccessoryView:container];
    
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        NSString *selectedVM = [popup titleOfSelectedItem];
        // Remove " (running)" suffix if present (shouldn't be selectable, but just in case)
        if ([selectedVM hasSuffix:@" (running)"]) {
            return;
        }
        NSString *isoPath = [isoInput stringValue];
        startVMGoCallback([selectedVM UTF8String], [isoPath UTF8String]);
    }
}

- (void)newVMFromURL:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Create New VM"];
    [alert setInformativeText:@"Enter a name and ISO path for the new VM:"];
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];
    
    // Create a container view for both fields
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 60)];
    
    // VM Name field (top)
    NSTextField *nameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 36, 60, 20)];
    [nameLabel setStringValue:@"Name:"];
    [nameLabel setBezeled:NO];
    [nameLabel setDrawsBackground:NO];
    [nameLabel setEditable:NO];
    [nameLabel setSelectable:NO];
    [container addSubview:nameLabel];
    
    NSTextField *nameInput = [[NSTextField alloc] initWithFrame:NSMakeRect(60, 34, 340, 24)];
    
    // Generate default name based on timestamp
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd-HHmmss"];
    NSString *defaultName = [NSString stringWithFormat:@"vm-%@", [formatter stringFromDate:[NSDate date]]];
    [nameInput setStringValue:defaultName];
    [nameInput setPlaceholderString:@"my-vm"];
    [container addSubview:nameInput];
    
    // ISO Path field (bottom)
    NSTextField *isoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 6, 60, 20)];
    [isoLabel setStringValue:@"ISO:"];
    [isoLabel setBezeled:NO];
    [isoLabel setDrawsBackground:NO];
    [isoLabel setEditable:NO];
    [isoLabel setSelectable:NO];
    [container addSubview:isoLabel];
    
    NSTextField *isoInput = [[NSTextField alloc] initWithFrame:NSMakeRect(60, 4, 340, 24)];
    [isoInput setStringValue:@""];
    [isoInput setPlaceholderString:@"/path/to/image.iso"];
    [container addSubview:isoInput];
    
    [alert setAccessoryView:container];
    [alert.window setInitialFirstResponder:nameInput];
    
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        NSString *vmName = [nameInput stringValue];
        NSString *isoPath = [isoInput stringValue];
        if (vmName.length > 0 && isoPath.length > 0) {
            newVMFromURLGoCallback([isoPath UTF8String], [vmName UTF8String]);
        }
    }
}

@end

// C function to call from Go to set up the File menu
void setupAppFileMenu(void)
{
    if ([NSThread isMainThread]) {
        [[FileMenuHandler sharedHandler] setupFileMenu];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [[FileMenuHandler sharedHandler] setupFileMenu];
        });
    }
}

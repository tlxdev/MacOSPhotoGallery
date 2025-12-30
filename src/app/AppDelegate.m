/**
 * AppDelegate.m
 * Application delegate implementation
 */

#import "AppDelegate.h"
#import "MainWindowController.h"
#import "RecentsManager.h"

static const NSInteger kRecentMenuItemTag = 1000;

@interface AppDelegate ()

@property (nonatomic, strong, readwrite) MainWindowController *mainWindowController;
@property (nonatomic, strong) NSMenu *recentsMenu;

@end

@implementation AppDelegate

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self setupMenuBar];
    [self createMainWindow];
    
    /* Listen for recents changes */
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(recentsDidChange:)
                                                 name:RecentsDidChangeNotification
                                               object:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

#pragma mark - Window Management

- (void)createMainWindow {
    self.mainWindowController = [[MainWindowController alloc] init];
    [self.mainWindowController showWindow:nil];
    [self.mainWindowController.window makeKeyAndOrderFront:nil];
}

#pragma mark - Menu Bar

- (void)setupMenuBar {
    NSMenu *mainMenu = [[NSMenu alloc] init];
    
    /* Application Menu */
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];
    
    [appMenu addItemWithTitle:@"About PhotoViewer"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    
    [appMenu addItem:[NSMenuItem separatorItem]];
    
    [appMenu addItemWithTitle:@"Hide PhotoViewer"
                       action:@selector(hide:)
                keyEquivalent:@"h"];
    
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others"
                                                action:@selector(hideOtherApplications:)
                                         keyEquivalent:@"h"];
    [hideOthers setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagOption];
    
    [appMenu addItemWithTitle:@"Show All"
                       action:@selector(unhideAllApplications:)
                keyEquivalent:@""];
    
    [appMenu addItem:[NSMenuItem separatorItem]];
    
    [appMenu addItemWithTitle:@"Quit PhotoViewer"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    
    [appMenuItem setSubmenu:appMenu];
    [mainMenu addItem:appMenuItem];
    
    /* File Menu */
    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] init];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    
    [fileMenu addItemWithTitle:@"Open Folder..."
                        action:@selector(openFolder:)
                 keyEquivalent:@"o"];
    
    /* Open Recent submenu */
    NSMenuItem *recentMenuItem = [[NSMenuItem alloc] initWithTitle:@"Open Recent"
                                                            action:nil
                                                     keyEquivalent:@""];
    self.recentsMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    [recentMenuItem setSubmenu:self.recentsMenu];
    [fileMenu addItem:recentMenuItem];
    
    [self updateRecentsMenu];
    
    [fileMenu addItem:[NSMenuItem separatorItem]];
    
    [fileMenu addItemWithTitle:@"Close Window"
                        action:@selector(performClose:)
                 keyEquivalent:@"w"];
    
    [fileMenuItem setSubmenu:fileMenu];
    [mainMenu addItem:fileMenuItem];
    
    /* Edit Menu */
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    
    [editMenu addItemWithTitle:@"Copy Image"
                        action:@selector(copyCurrentPhoto:)
                 keyEquivalent:@"c"];
    
    [editMenuItem setSubmenu:editMenu];
    [mainMenu addItem:editMenuItem];
    
    /* View Menu */
    NSMenuItem *viewMenuItem = [[NSMenuItem alloc] init];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    
    [viewMenu addItemWithTitle:@"Toggle Grid View"
                        action:@selector(toggleGridView:)
                 keyEquivalent:@"g"];
    
    [viewMenu addItemWithTitle:@"Toggle Metadata"
                        action:@selector(toggleMetadata:)
                 keyEquivalent:@"i"];
    
    [viewMenu addItem:[NSMenuItem separatorItem]];
    
    [viewMenu addItemWithTitle:@"Zoom In"
                        action:@selector(zoomIn:)
                 keyEquivalent:@"+"];
    
    [viewMenu addItemWithTitle:@"Zoom Out"
                        action:@selector(zoomOut:)
                 keyEquivalent:@"-"];
    
    [viewMenu addItemWithTitle:@"Actual Size"
                        action:@selector(zoomToActualSize:)
                 keyEquivalent:@"0"];
    
    [viewMenu addItemWithTitle:@"Fit to Window"
                        action:@selector(zoomToFit:)
                 keyEquivalent:@"9"];
    
    [viewMenu addItem:[NSMenuItem separatorItem]];
    
    [viewMenu addItemWithTitle:@"Enter Full Screen"
                        action:@selector(toggleFullScreen:)
                 keyEquivalent:@"f"];
    
    [viewMenuItem setSubmenu:viewMenu];
    [mainMenu addItem:viewMenuItem];
    
    /* Go Menu */
    NSMenuItem *goMenuItem = [[NSMenuItem alloc] init];
    NSMenu *goMenu = [[NSMenu alloc] initWithTitle:@"Go"];
    
    NSMenuItem *prevItem = [goMenu addItemWithTitle:@"Previous Photo"
                                             action:@selector(previousPhoto:)
                                      keyEquivalent:@""];
    prevItem.keyEquivalentModifierMask = 0;
    
    NSMenuItem *nextItem = [goMenu addItemWithTitle:@"Next Photo"
                                             action:@selector(nextPhoto:)
                                      keyEquivalent:@""];
    nextItem.keyEquivalentModifierMask = 0;
    
    [goMenuItem setSubmenu:goMenu];
    [mainMenu addItem:goMenuItem];
    
    /* Window Menu */
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    
    [windowMenu addItemWithTitle:@"Minimize"
                          action:@selector(performMiniaturize:)
                   keyEquivalent:@"m"];
    
    [windowMenu addItemWithTitle:@"Zoom"
                          action:@selector(performZoom:)
                   keyEquivalent:@""];
    
    [windowMenuItem setSubmenu:windowMenu];
    [mainMenu addItem:windowMenuItem];
    
    [NSApp setMainMenu:mainMenu];
    [NSApp setWindowsMenu:windowMenu];
}

#pragma mark - Recents Menu

- (void)updateRecentsMenu {
    [self.recentsMenu removeAllItems];
    
    RecentsManager *manager = [RecentsManager sharedManager];
    NSArray *recents = manager.recentFolders;
    
    if (recents.count == 0) {
        NSMenuItem *emptyItem = [[NSMenuItem alloc] initWithTitle:@"No Recent Folders"
                                                           action:nil
                                                    keyEquivalent:@""];
        emptyItem.enabled = NO;
        [self.recentsMenu addItem:emptyItem];
    } else {
        NSInteger index = 0;
        for (NSString *path in recents) {
            NSString *displayName = [manager displayNameForPath:path];
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:displayName
                                                          action:@selector(openRecentFolder:)
                                                   keyEquivalent:@""];
            item.target = self;
            item.tag = kRecentMenuItemTag + index;
            item.representedObject = path;
            item.toolTip = path;
            
            /* Add folder icon */
            item.image = [NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:nil];
            
            [self.recentsMenu addItem:item];
            index++;
        }
        
        [self.recentsMenu addItem:[NSMenuItem separatorItem]];
        
        NSMenuItem *clearItem = [[NSMenuItem alloc] initWithTitle:@"Clear Recents"
                                                           action:@selector(clearRecents:)
                                                    keyEquivalent:@""];
        clearItem.target = self;
        [self.recentsMenu addItem:clearItem];
    }
}

- (void)recentsDidChange:(NSNotification *)notification {
    [self updateRecentsMenu];
}

#pragma mark - Actions

- (void)openFolder:(id)sender {
    [self.mainWindowController openFolder:sender];
}

- (void)openRecentFolder:(NSMenuItem *)sender {
    NSString *path = sender.representedObject;
    if (path) {
        [self.mainWindowController openFolderAtPath:path];
    }
}

- (void)clearRecents:(id)sender {
    [[RecentsManager sharedManager] clearRecents];
}

@end

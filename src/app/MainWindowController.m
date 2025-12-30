/**
 * MainWindowController.m
 * Main window controller implementation
 */

#import "MainWindowController.h"
#import "RecentsManager.h"
#import "../models/PhotoStore.h"
#import "../models/PhotoItem.h"
#import "../views/PhotoView.h"
#import "../views/PhotoGridView.h"
#import "../views/MetadataPanel.h"
#import "../views/ToolbarView.h"
#import "../views/ThumbnailCache.h"
#import "../utils/Theme.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static const CGFloat kWindowMinWidth = 800.0;
static const CGFloat kWindowMinHeight = 600.0;
static const CGFloat kToolbarHeight = 48.0;
static const CGFloat kMetadataPanelWidth = 280.0;

@interface MainWindowController ()

@property (nonatomic, strong, readwrite) PhotoStore *photoStore;
@property (nonatomic, assign, readwrite) BOOL isGridViewVisible;
@property (nonatomic, assign, readwrite) BOOL isMetadataVisible;

@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) ToolbarView *toolbarView;
@property (nonatomic, strong) PhotoView *photoView;
@property (nonatomic, strong) PhotoGridView *gridView;
@property (nonatomic, strong) MetadataPanel *metadataPanel;
@property (nonatomic, strong) NSView *welcomeView;

@property (nonatomic, strong) NSLayoutConstraint *metadataWidthConstraint;

@end

@implementation MainWindowController

#pragma mark - Initialization

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 1400, 900);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                              NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable |
                              NSWindowStyleMaskResizable |
                              NSWindowStyleMaskFullSizeContentView;
    
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    
    self = [super initWithWindow:window];
    if (self) {
        [self setupWindow];
        [self setupPhotoStore];
        [self setupViews];
        [self setupKeyboardMonitor];
        [self showWelcomeView];
    }
    return self;
}

#pragma mark - Window Setup

- (void)setupWindow {
    NSWindow *window = self.window;
    
    window.title = @"PhotoViewer";
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
    window.backgroundColor = [Theme backgroundColor];
    window.minSize = NSMakeSize(kWindowMinWidth, kWindowMinHeight);
    window.delegate = self;
    
    /* Center on screen */
    [window center];
    
    /* Enable fullscreen */
    window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
}

- (void)setupPhotoStore {
    self.photoStore = [[PhotoStore alloc] init];
    
    __weak typeof(self) weakSelf = self;
    self.photoStore.onSelectionChanged = ^(NSUInteger index) {
        [weakSelf handleSelectionChanged:index];
    };
    self.photoStore.onPhotosLoaded = ^(NSUInteger count) {
        [weakSelf handlePhotosLoaded:count];
    };
    self.photoStore.onError = ^(NSError *error) {
        [weakSelf handleError:error];
    };
    self.photoStore.onFolderChanged = ^{
        [weakSelf handleFolderChanged];
    };
}

#pragma mark - View Setup

- (void)setupViews {
    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;
    contentView.layer.backgroundColor = [Theme backgroundCGColor];
    
    /* Content container */
    self.contentContainer = [[NSView alloc] init];
    self.contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentContainer.wantsLayer = YES;
    [contentView addSubview:self.contentContainer];
    
    /* Toolbar */
    self.toolbarView = [[ToolbarView alloc] initWithController:self];
    self.toolbarView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:self.toolbarView];
    
    /* Photo view */
    self.photoView = [[PhotoView alloc] initWithPhotoStore:self.photoStore];
    self.photoView.translatesAutoresizingMaskIntoConstraints = NO;
    self.photoView.hidden = YES;
    [self.contentContainer addSubview:self.photoView];
    
    /* Grid view */
    self.gridView = [[PhotoGridView alloc] initWithPhotoStore:self.photoStore];
    self.gridView.translatesAutoresizingMaskIntoConstraints = NO;
    self.gridView.hidden = YES;
    [self.contentContainer addSubview:self.gridView];
    
    /* Metadata panel */
    self.metadataPanel = [[MetadataPanel alloc] initWithPhotoStore:self.photoStore];
    self.metadataPanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.metadataPanel.hidden = YES;
    [contentView addSubview:self.metadataPanel];
    
    /* Layout */
    [NSLayoutConstraint activateConstraints:@[
        /* Toolbar */
        [self.toolbarView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [self.toolbarView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.toolbarView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.toolbarView.heightAnchor constraintEqualToConstant:kToolbarHeight],
        
        /* Content container */
        [self.contentContainer.topAnchor constraintEqualToAnchor:self.toolbarView.bottomAnchor],
        [self.contentContainer.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.contentContainer.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        
        /* Photo view fills content */
        [self.photoView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [self.photoView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [self.photoView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [self.photoView.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
        
        /* Grid view fills content */
        [self.gridView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [self.gridView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [self.gridView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [self.gridView.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
        
        /* Metadata panel */
        [self.metadataPanel.topAnchor constraintEqualToAnchor:self.toolbarView.bottomAnchor],
        [self.metadataPanel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.metadataPanel.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
    ]];
    
    /* Metadata width constraint */
    self.metadataWidthConstraint = [self.metadataPanel.widthAnchor constraintEqualToConstant:0];
    self.metadataWidthConstraint.active = YES;
    
    /* Content container trailing depends on metadata */
    NSLayoutConstraint *contentTrailing = [self.contentContainer.trailingAnchor constraintEqualToAnchor:self.metadataPanel.leadingAnchor];
    contentTrailing.active = YES;
}

- (void)showWelcomeView {
    if (self.welcomeView) {
        return;
    }
    
    self.welcomeView = [[NSView alloc] init];
    self.welcomeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.welcomeView.wantsLayer = YES;
    [self.contentContainer addSubview:self.welcomeView];
    
    /* Center content */
    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 24;
    [self.welcomeView addSubview:stack];
    
    /* Icon */
    NSImageView *iconView = [[NSImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.image = [NSImage imageWithSystemSymbolName:@"photo.on.rectangle.angled" accessibilityDescription:nil];
    iconView.contentTintColor = [Theme accentColor];
    iconView.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:64 weight:NSFontWeightLight];
    [stack addArrangedSubview:iconView];
    
    /* Title */
    NSTextField *title = [NSTextField labelWithString:@"PhotoViewer"];
    title.font = [NSFont systemFontOfSize:28 weight:NSFontWeightLight];
    title.textColor = [Theme textColor];
    [stack addArrangedSubview:title];
    
    /* Subtitle */
    NSTextField *subtitle = [NSTextField labelWithString:@"High-performance viewing for your photo library"];
    subtitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    subtitle.textColor = [Theme tertiaryTextColor];
    [stack addArrangedSubview:subtitle];
    
    /* Open button */
    NSButton *openButton = [[NSButton alloc] init];
    openButton.translatesAutoresizingMaskIntoConstraints = NO;
    openButton.title = @"Open Folder";
    openButton.bezelStyle = NSBezelStyleRounded;
    openButton.controlSize = NSControlSizeLarge;
    openButton.target = self;
    openButton.action = @selector(openFolder:);
    openButton.keyEquivalent = @"\r";
    [stack addArrangedSubview:openButton];
    
    /* Recents section */
    NSArray *recents = [[RecentsManager sharedManager] recentFolders];
    if (recents.count > 0) {
        /* Spacer */
        NSView *spacer = [[NSView alloc] init];
        spacer.translatesAutoresizingMaskIntoConstraints = NO;
        [spacer.heightAnchor constraintEqualToConstant:8].active = YES;
        [stack addArrangedSubview:spacer];
        
        /* Recents label */
        NSTextField *recentsLabel = [NSTextField labelWithString:@"Recent Folders"];
        recentsLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        recentsLabel.textColor = [Theme tertiaryTextColor];
        [stack addArrangedSubview:recentsLabel];
        
        /* Recents list (show up to 5) */
        NSUInteger maxToShow = MIN(recents.count, 5);
        for (NSUInteger i = 0; i < maxToShow; i++) {
            NSString *path = recents[i];
            NSButton *recentButton = [self createRecentButtonForPath:path];
            [stack addArrangedSubview:recentButton];
        }
    }
    
    /* Keyboard hints */
    NSTextField *hints = [NSTextField labelWithString:@"Arrow keys to navigate  |  G for grid  |  I for info"];
    hints.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    hints.textColor = [Theme tertiaryTextColor];
    [stack addArrangedSubview:hints];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.welcomeView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [self.welcomeView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [self.welcomeView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [self.welcomeView.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
        
        [stack.centerXAnchor constraintEqualToAnchor:self.welcomeView.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.welcomeView.centerYAnchor],
        
        [openButton.widthAnchor constraintGreaterThanOrEqualToConstant:140],
    ]];
}

- (NSButton *)createRecentButtonForPath:(NSString *)path {
    NSButton *button = [[NSButton alloc] init];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleAccessoryBarAction;
    button.bordered = NO;
    
    /* Folder icon */
    NSImage *folderIcon = [NSImage imageWithSystemSymbolName:@"folder.fill" accessibilityDescription:nil];
    button.image = folderIcon;
    button.imagePosition = NSImageLeft;
    button.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightRegular];
    
    /* Folder name */
    button.title = path.lastPathComponent;
    button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
    button.contentTintColor = [Theme secondaryTextColor];
    
    /* Store path and set action */
    button.toolTip = path;
    button.target = self;
    button.action = @selector(openRecentFromWelcome:);
    
    /* Use associated object to store path */
    objc_setAssociatedObject(button, "recentPath", path, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
    
    return button;
}

- (void)openRecentFromWelcome:(NSButton *)sender {
    NSString *path = objc_getAssociatedObject(sender, "recentPath");
    if (path) {
        [self openFolderAtPath:path];
    }
}

- (void)hideWelcomeView {
    [self.welcomeView removeFromSuperview];
    self.welcomeView = nil;
}

#pragma mark - Keyboard Monitor

- (void)setupKeyboardMonitor {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if ([self handleKeyDown:event]) {
            return nil;
        }
        return event;
    }];
}

- (BOOL)handleKeyDown:(NSEvent *)event {
    if (self.photoStore.photoCount == 0) {
        return NO;
    }
    
    switch (event.keyCode) {
        case 123: /* Left arrow */
            [self previousPhoto:nil];
            return YES;
        case 124: /* Right arrow */
            [self nextPhoto:nil];
            return YES;
        case 8: /* C */
            if (event.modifierFlags & NSEventModifierFlagCommand) {
                [self copyCurrentPhoto:nil];
                return YES;
            }
            break;
        case 5: /* G */
            if (!(event.modifierFlags & NSEventModifierFlagCommand)) {
                [self toggleGridView:nil];
                return YES;
            }
            break;
        case 34: /* I */
            if (!(event.modifierFlags & NSEventModifierFlagCommand)) {
                [self toggleMetadata:nil];
                return YES;
            }
            break;
        case 53: /* Escape */
            [self zoomToFit:nil];
            return YES;
        default:
            break;
    }
    
    return NO;
}

#pragma mark - Event Handlers

- (void)handleSelectionChanged:(NSUInteger)index {
    [self.toolbarView updateForPhoto];
    [self.photoView displayCurrentPhoto];
    
    if (self.isMetadataVisible) {
        [self.metadataPanel refresh];
    }
}

- (void)handlePhotosLoaded:(NSUInteger)count {
    if (count > 0) {
        [self hideWelcomeView];
        self.photoView.hidden = self.isGridViewVisible;
        self.gridView.hidden = !self.isGridViewVisible;
        [self.toolbarView updateForPhoto];
        [self.photoView displayCurrentPhoto];
        [self.gridView reloadData];
        
        /* Start background thumbnail preloading */
        [self startThumbnailPreloading];
    }
}

- (void)handleError:(NSError *)error {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Error";
    alert.informativeText = error.localizedDescription;
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)handleFolderChanged {
    /* Show brief notification that folder changed */
    /* Auto-rescan the folder to pick up changes */
    [self.photoStore rescanCurrentFolder];
}

- (void)startThumbnailPreloading {
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:self.photoStore.photoCount];
    
    for (NSUInteger i = 0; i < self.photoStore.photoCount; i++) {
        PhotoItem *photo = [self.photoStore photoAtIndex:i];
        if (photo) {
            [paths addObject:photo.path];
        }
    }
    
    [[ThumbnailCache sharedCache] preloadThumbnailsForPaths:paths];
}

#pragma mark - Actions

- (void)openFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Select a folder containing photos";
    panel.prompt = @"Open";
    
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            [self openFolderAtPath:panel.URL.path];
        }
    }];
}

- (void)openFolderAtPath:(NSString *)path {
    if (!path) {
        return;
    }
    
    if ([self.photoStore scanDirectory:path]) {
        /* Add to recents on successful scan start */
        [[RecentsManager sharedManager] addRecentFolder:path];
    }
}

- (void)toggleGridView:(id)sender {
    self.isGridViewVisible = !self.isGridViewVisible;
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.2;
        self.photoView.animator.hidden = self.isGridViewVisible;
        self.gridView.animator.hidden = !self.isGridViewVisible;
    }];
    
    [self.toolbarView updateForViewMode];
    
    if (!self.isGridViewVisible) {
        [self.photoView displayCurrentPhoto];
    }
}

- (void)toggleMetadata:(id)sender {
    self.isMetadataVisible = !self.isMetadataVisible;
    
    CGFloat width = self.isMetadataVisible ? kMetadataPanelWidth : 0;
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.25;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        self.metadataWidthConstraint.animator.constant = width;
        self.metadataPanel.animator.hidden = !self.isMetadataVisible;
    }];
    
    if (self.isMetadataVisible) {
        [self.metadataPanel refresh];
    }
    
    [self.toolbarView updateForMetadataVisibility];
}

- (void)previousPhoto:(id)sender {
    [self.photoStore selectPrevious];
}

- (void)nextPhoto:(id)sender {
    [self.photoStore selectNext];
}

- (void)zoomIn:(id)sender {
    [self.photoView zoomIn];
}

- (void)zoomOut:(id)sender {
    [self.photoView zoomOut];
}

- (void)zoomToActualSize:(id)sender {
    [self.photoView zoomToActualSize];
}

- (void)zoomToFit:(id)sender {
    [self.photoView zoomToFit];
}

- (void)shareCurrentPhoto:(id)sender {
    PhotoItem *photo = [self.photoStore currentPhoto];
    if (!photo) {
        return;
    }
    
    NSURL *fileURL = [NSURL fileURLWithPath:photo.path];
    NSSharingServicePicker *picker = [[NSSharingServicePicker alloc] initWithItems:@[fileURL]];
    
    NSView *sourceView = self.toolbarView;
    NSRect rect = NSMakeRect(sourceView.bounds.size.width - 100, 0, 40, sourceView.bounds.size.height);
    [picker showRelativeToRect:rect ofView:sourceView preferredEdge:NSRectEdgeMinY];
}

- (void)showInFinder:(id)sender {
    PhotoItem *photo = [self.photoStore currentPhoto];
    if (photo) {
        [[NSWorkspace sharedWorkspace] selectFile:photo.path inFileViewerRootedAtPath:@""];
    }
}

- (void)copyCurrentPhoto:(id)sender {
    PhotoItem *photo = [self.photoStore currentPhoto];
    if (!photo) {
        return;
    }
    
    /* Load the full image */
    NSURL *url = [NSURL fileURLWithPath:photo.path];
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    
    if (!image) {
        return;
    }
    
    /* Copy to pasteboard */
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard writeObjects:@[image]];
}

#pragma mark - NSWindowDelegate

- (void)windowDidBecomeKey:(NSNotification *)notification {
    /* Refresh if needed */
}

@end


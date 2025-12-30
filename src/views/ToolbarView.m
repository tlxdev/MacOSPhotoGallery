/**
 * ToolbarView.m
 * Toolbar implementation
 */

#import "ToolbarView.h"
#import "../app/MainWindowController.h"
#import "../models/PhotoStore.h"
#import "../models/PhotoItem.h"

static const CGFloat kButtonSize = 32.0;
static const CGFloat kButtonSpacing = 4.0;

@interface ToolbarView ()

@property (nonatomic, weak) MainWindowController *controller;

/* Left section */
@property (nonatomic, strong) NSButton *folderButton;
@property (nonatomic, strong) NSTextField *photoCountLabel;

/* Center section */
@property (nonatomic, strong) NSTextField *indexLabel;

/* Right section */
@property (nonatomic, strong) NSButton *gridButton;
@property (nonatomic, strong) NSButton *infoButton;
@property (nonatomic, strong) NSButton *finderButton;
@property (nonatomic, strong) NSButton *shareButton;

@end

@implementation ToolbarView

- (instancetype)initWithController:(MainWindowController *)controller {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _controller = controller;
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    self.wantsLayer = YES;
    self.layer.backgroundColor = [NSColor colorWithRed:0.035 green:0.035 blue:0.043 alpha:0.9].CGColor;
    
    /* Left stack */
    NSStackView *leftStack = [[NSStackView alloc] init];
    leftStack.translatesAutoresizingMaskIntoConstraints = NO;
    leftStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    leftStack.spacing = 12;
    [self addSubview:leftStack];
    
    /* Folder button - custom setup for flexible width */
    self.folderButton = [[NSButton alloc] init];
    self.folderButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.folderButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    self.folderButton.bordered = NO;
    self.folderButton.image = [NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:nil];
    self.folderButton.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightRegular];
    self.folderButton.imagePosition = NSImageLeft;
    self.folderButton.title = @"Open Folder";
    self.folderButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.folderButton.contentTintColor = [NSColor colorWithWhite:0.85 alpha:1.0];
    self.folderButton.target = self.controller;
    self.folderButton.action = @selector(openFolder:);
    self.folderButton.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.folderButton setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [leftStack addArrangedSubview:self.folderButton];
    
    /* Limit max width for folder name */
    [self.folderButton.widthAnchor constraintLessThanOrEqualToConstant:300].active = YES;
    
    /* Photo count */
    self.photoCountLabel = [NSTextField labelWithString:@""];
    self.photoCountLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    self.photoCountLabel.textColor = [NSColor colorWithWhite:0.5 alpha:1.0];
    [leftStack addArrangedSubview:self.photoCountLabel];
    
    /* Center - index label */
    self.indexLabel = [NSTextField labelWithString:@""];
    self.indexLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.indexLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.indexLabel.textColor = [NSColor colorWithWhite:0.5 alpha:1.0];
    self.indexLabel.alignment = NSTextAlignmentCenter;
    [self addSubview:self.indexLabel];
    
    /* Right stack */
    NSStackView *rightStack = [[NSStackView alloc] init];
    rightStack.translatesAutoresizingMaskIntoConstraints = NO;
    rightStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    rightStack.spacing = kButtonSpacing;
    [self addSubview:rightStack];
    
    self.gridButton = [self createButtonWithSymbol:@"square.grid.2x2" action:@selector(toggleGridView:)];
    self.gridButton.toolTip = @"Toggle Grid View (G)";
    [rightStack addArrangedSubview:self.gridButton];
    
    self.infoButton = [self createButtonWithSymbol:@"info.circle" action:@selector(toggleMetadata:)];
    self.infoButton.toolTip = @"Toggle Info Panel (I)";
    [rightStack addArrangedSubview:self.infoButton];
    
    self.finderButton = [self createButtonWithSymbol:@"arrow.up.forward.square" action:@selector(showInFinder:)];
    self.finderButton.toolTip = @"Show in Finder";
    [rightStack addArrangedSubview:self.finderButton];
    
    self.shareButton = [self createButtonWithSymbol:@"square.and.arrow.up" action:@selector(shareCurrentPhoto:)];
    self.shareButton.toolTip = @"Share";
    [rightStack addArrangedSubview:self.shareButton];
    
    /* Layout */
    [NSLayoutConstraint activateConstraints:@[
        [leftStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:80], /* After traffic lights */
        [leftStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        
        [self.indexLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.indexLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        
        [rightStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [rightStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
}

- (NSButton *)createButtonWithSymbol:(NSString *)symbolName action:(SEL)action {
    NSButton *button = [[NSButton alloc] init];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleAccessoryBarAction;
    button.bordered = NO;
    button.image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
    button.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightRegular];
    button.contentTintColor = [NSColor colorWithWhite:0.7 alpha:1.0];
    button.target = self.controller;
    button.action = action;
    
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:kButtonSize],
        [button.heightAnchor constraintEqualToConstant:kButtonSize],
    ]];
    
    return button;
}

#pragma mark - Updates

- (void)updateForPhoto {
    PhotoStore *store = self.controller.photoStore;
    
    if (store.photoCount == 0) {
        self.photoCountLabel.stringValue = @"";
        self.indexLabel.stringValue = @"";
        return;
    }
    
    self.photoCountLabel.stringValue = [NSString stringWithFormat:@"%lu photos", (unsigned long)store.photoCount];
    self.indexLabel.stringValue = [NSString stringWithFormat:@"%lu / %lu", 
                                   (unsigned long)store.selectedIndex + 1,
                                   (unsigned long)store.photoCount];
    
    if (store.folderName) {
        self.folderButton.title = store.folderName;
    }
}

- (void)updateForViewMode {
    BOOL isGrid = self.controller.isGridViewVisible;
    self.gridButton.contentTintColor = isGrid ? 
        [NSColor colorWithRed:0.055 green:0.647 blue:0.914 alpha:1.0] :
        [NSColor colorWithWhite:0.7 alpha:1.0];
}

- (void)updateForMetadataVisibility {
    BOOL isVisible = self.controller.isMetadataVisible;
    self.infoButton.contentTintColor = isVisible ?
        [NSColor colorWithRed:0.055 green:0.647 blue:0.914 alpha:1.0] :
        [NSColor colorWithWhite:0.7 alpha:1.0];
}

@end


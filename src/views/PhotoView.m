/**
 * PhotoView.m
 * Photo display view with zoom/pan - centered image display
 */

#import "PhotoView.h"
#import "../models/PhotoStore.h"
#import "../models/PhotoItem.h"
#import "../utils/Theme.h"

static const CGFloat kZoomStep = 1.5;
static const CGFloat kMinZoom = 0.1;
static const CGFloat kMaxZoom = 10.0;

/* Centered clip view for proper image centering */
@interface CenteredClipView : NSClipView
@end

@implementation CenteredClipView

- (NSRect)constrainBoundsRect:(NSRect)proposedBounds {
    NSRect constrainedBounds = [super constrainBoundsRect:proposedBounds];
    NSRect documentFrame = self.documentView.frame;
    
    /* Center horizontally if document is smaller than clip view */
    if (documentFrame.size.width < constrainedBounds.size.width) {
        constrainedBounds.origin.x = (documentFrame.size.width - constrainedBounds.size.width) / 2.0;
    }
    
    /* Center vertically if document is smaller than clip view */
    if (documentFrame.size.height < constrainedBounds.size.height) {
        constrainedBounds.origin.y = (documentFrame.size.height - constrainedBounds.size.height) / 2.0;
    }
    
    return constrainedBounds;
}

@end

@interface PhotoView ()

@property (nonatomic, weak, readwrite) PhotoStore *photoStore;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSImageView *imageView;
@property (nonatomic, strong) NSProgressIndicator *loadingIndicator;
@property (nonatomic, strong) NSTextField *errorLabel;
@property (nonatomic, copy) NSString *currentPath;

@end

@implementation PhotoView

- (instancetype)initWithPhotoStore:(PhotoStore *)photoStore {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _photoStore = photoStore;
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    self.wantsLayer = YES;
    self.layer.backgroundColor = [Theme backgroundCGColor];
    
    /* Scroll view for zoom/pan */
    self.scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.hasHorizontalScroller = YES;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.backgroundColor = [Theme backgroundColor];
    self.scrollView.drawsBackground = YES;
    self.scrollView.allowsMagnification = YES;
    self.scrollView.minMagnification = kMinZoom;
    self.scrollView.maxMagnification = kMaxZoom;
    
    /* Use centered clip view */
    CenteredClipView *clipView = [[CenteredClipView alloc] init];
    clipView.drawsBackground = NO;
    self.scrollView.contentView = clipView;
    
    [self addSubview:self.scrollView];
    
    /* Image view */
    self.imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    self.imageView.imageScaling = NSImageScaleNone;
    self.imageView.imageAlignment = NSImageAlignCenter;
    self.imageView.wantsLayer = YES;
    self.scrollView.documentView = self.imageView;
    
    /* Loading indicator */
    self.loadingIndicator = [[NSProgressIndicator alloc] init];
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.style = NSProgressIndicatorStyleSpinning;
    self.loadingIndicator.controlSize = NSControlSizeRegular;
    self.loadingIndicator.hidden = YES;
    [self addSubview:self.loadingIndicator];
    
    /* Error label */
    self.errorLabel = [NSTextField labelWithString:@""];
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    self.errorLabel.textColor = [Theme tertiaryTextColor];
    self.errorLabel.alignment = NSTextAlignmentCenter;
    self.errorLabel.hidden = YES;
    [self addSubview:self.errorLabel];
    
    /* Layout */
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        
        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        
        [self.errorLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.errorLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.errorLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:20],
        [self.errorLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-20],
    ]];
}

#pragma mark - Display

- (void)displayCurrentPhoto {
    PhotoItem *photo = [self.photoStore currentPhoto];
    if (!photo) {
        self.imageView.image = nil;
        self.errorLabel.hidden = YES;
        return;
    }
    
    /* Skip if same photo */
    if ([self.currentPath isEqualToString:photo.path]) {
        return;
    }
    
    self.currentPath = photo.path;
    
    /* Hide error, show loading */
    self.errorLabel.hidden = YES;
    self.loadingIndicator.hidden = NO;
    [self.loadingIndicator startAnimation:nil];
    
    /* Load image asynchronously */
    NSString *path = photo.path;
    NSString *fileName = photo.name;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSURL *url = [NSURL fileURLWithPath:path];
        
        /* Check if file exists first */
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL fileExists = [fm fileExistsAtPath:path];
        
        NSImage *image = nil;
        NSString *errorMessage = nil;
        
        if (!fileExists) {
            errorMessage = [NSString stringWithFormat:@"File not found: %@", fileName];
        } else if (![fm isReadableFileAtPath:path]) {
            errorMessage = [NSString stringWithFormat:@"Cannot read file: %@", fileName];
        } else {
            image = [[NSImage alloc] initWithContentsOfURL:url];
            if (!image) {
                /* Try to determine if it's a format issue */
                NSString *extension = path.pathExtension.lowercaseString;
                errorMessage = [NSString stringWithFormat:@"Unable to load image: %@\nFormat '%@' may be unsupported or file is corrupted", fileName, extension];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            /* Verify still current photo */
            if (![self.currentPath isEqualToString:path]) {
                return;
            }
            
            [self.loadingIndicator stopAnimation:nil];
            self.loadingIndicator.hidden = YES;
            
            if (image) {
                self.imageView.image = image;
                self.errorLabel.hidden = YES;
                
                /* Size image view to image size */
                NSSize imageSize = image.size;
                [self.imageView setFrameSize:imageSize];
                
                /* Reset magnification and fit */
                [self.scrollView setMagnification:1.0];
                [self zoomToFit];
            } else {
                /* Show error message */
                self.imageView.image = nil;
                self.errorLabel.stringValue = errorMessage ?: @"Unable to load image";
                self.errorLabel.hidden = NO;
            }
        });
    });
}

#pragma mark - Zoom

- (void)zoomIn {
    CGFloat newMagnification = self.scrollView.magnification * kZoomStep;
    [self.scrollView.animator setMagnification:MIN(newMagnification, kMaxZoom)];
}

- (void)zoomOut {
    CGFloat newMagnification = self.scrollView.magnification / kZoomStep;
    [self.scrollView.animator setMagnification:MAX(newMagnification, kMinZoom)];
}

- (void)zoomToActualSize {
    [self.scrollView.animator setMagnification:1.0];
}

- (void)zoomToFit {
    if (!self.imageView.image) {
        return;
    }
    
    NSSize imageSize = self.imageView.image.size;
    NSSize viewSize = self.scrollView.contentSize;
    
    if (imageSize.width <= 0 || imageSize.height <= 0 || 
        viewSize.width <= 0 || viewSize.height <= 0) {
        return;
    }
    
    CGFloat widthRatio = viewSize.width / imageSize.width;
    CGFloat heightRatio = viewSize.height / imageSize.height;
    CGFloat fitMagnification = MIN(widthRatio, heightRatio);
    
    /* Don't zoom above 100% for fit */
    fitMagnification = MIN(fitMagnification, 1.0);
    
    /* Ensure minimum visibility */
    fitMagnification = MAX(fitMagnification, kMinZoom);
    
    [self.scrollView setMagnification:fitMagnification];
}

#pragma mark - Layout

- (void)layout {
    [super layout];
    
    /* Re-fit when view resizes */
    if (self.imageView.image && !self.hidden) {
        [self zoomToFit];
    }
}

#pragma mark - Event Handling

- (void)scrollWheel:(NSEvent *)event {
    [super scrollWheel:event];
}

- (void)mouseDown:(NSEvent *)event {
    if (event.clickCount == 2) {
        [self zoomToFit];
    }
}

- (void)keyDown:(NSEvent *)event {
    [self.window.windowController keyDown:event];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

@end

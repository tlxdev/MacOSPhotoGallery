/**
 * MetadataPanel.m
 * Metadata panel implementation
 */

#import "MetadataPanel.h"
#import "../models/PhotoStore.h"
#import "../models/PhotoItem.h"
#import "../utils/Theme.h"
#import "../utils/DateFormatters.h"

/* Flipped view for top-to-bottom layout */
@interface FlippedView : NSView
@end

@implementation FlippedView
- (BOOL)isFlipped {
    return YES;
}
@end

@interface MetadataPanel ()

@property (nonatomic, weak, readwrite) PhotoStore *photoStore;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSStackView *contentStack;
@property (nonatomic, strong) FlippedView *documentView;

@end

@implementation MetadataPanel

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
    self.layer.backgroundColor = [Theme panelBackgroundCGColor];
    
    /* Scroll view */
    self.scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.backgroundColor = [Theme panelBackgroundColor];
    self.scrollView.drawsBackground = YES;
    [self addSubview:self.scrollView];
    
    /* Flipped document view for top alignment */
    self.documentView = [[FlippedView alloc] init];
    self.documentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.documentView = self.documentView;
    
    /* Content stack */
    self.contentStack = [[NSStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.contentStack.alignment = NSLayoutAttributeLeading;
    self.contentStack.spacing = 12;
    [self.documentView addSubview:self.contentStack];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        
        [self.contentStack.topAnchor constraintEqualToAnchor:self.documentView.topAnchor constant:16],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.documentView.leadingAnchor constant:16],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.documentView.trailingAnchor constant:-16],
        [self.contentStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.documentView.bottomAnchor constant:-16],
        
        /* Document view width matches scroll view */
        [self.documentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
    ]];
}

- (void)refresh {
    /* Clear existing content */
    for (NSView *view in self.contentStack.arrangedSubviews.copy) {
        [self.contentStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    
    PhotoItem *photo = [self.photoStore currentPhoto];
    if (!photo) {
        return;
    }
    
    /* Load metadata if needed */
    [photo loadMetadata];
    
    /* File name header */
    NSTextField *nameLabel = [NSTextField labelWithString:photo.name];
    nameLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    nameLabel.textColor = [Theme textColor];
    nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.contentStack addArrangedSubview:nameLabel];
    
    [self addSeparator];
    
    /* File info */
    [self addSectionTitle:@"FILE"];
    [self addRow:@"Size" value:[PhotoItem formattedFileSize:photo.fileSize]];
    [self addRow:@"Created" value:[self formatDate:photo.createdDate]];
    
    /* Image info */
    [self addSeparator];
    [self addSectionTitle:@"IMAGE"];
    if (photo.dimensions.width > 0) {
        NSString *dims = [NSString stringWithFormat:@"%.0f x %.0f", 
                         photo.dimensions.width, photo.dimensions.height];
        [self addRow:@"Dimensions" value:dims];
    }
    if (photo.colorSpace) {
        [self addRow:@"Color Space" value:photo.colorSpace];
    }
    if (photo.dateTaken) {
        [self addRow:@"Date Taken" value:[self formatDate:photo.dateTaken]];
    }
    
    /* Camera info */
    if (photo.cameraMake || photo.cameraModel) {
        [self addSeparator];
        [self addSectionTitle:@"CAMERA"];
        if (photo.cameraMake) {
            [self addRow:@"Make" value:photo.cameraMake];
        }
        if (photo.cameraModel) {
            [self addRow:@"Model" value:photo.cameraModel];
        }
    }
    
    /* Exposure info */
    if (photo.exposureTime || photo.fNumber || photo.iso || photo.focalLength) {
        [self addSeparator];
        [self addSectionTitle:@"EXPOSURE"];
        if (photo.exposureTime) {
            [self addRow:@"Shutter" value:photo.exposureTime];
        }
        if (photo.fNumber) {
            [self addRow:@"Aperture" value:photo.fNumber];
        }
        if (photo.iso) {
            [self addRow:@"ISO" value:[NSString stringWithFormat:@"%@", photo.iso]];
        }
        if (photo.focalLength) {
            [self addRow:@"Focal Length" value:photo.focalLength];
        }
    }
    
    /* Force layout update */
    [self.documentView setNeedsLayout:YES];
    [self.documentView layoutSubtreeIfNeeded];
    
    /* Update document view height to fit content */
    CGFloat contentHeight = self.contentStack.fittingSize.height + 32;
    [self.documentView setFrameSize:NSMakeSize(self.scrollView.contentSize.width, contentHeight)];
}

#pragma mark - Helpers

- (void)addSectionTitle:(NSString *)title {
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
    label.textColor = [Theme tertiaryTextColor];
    [self.contentStack addArrangedSubview:label];
}

- (void)addRow:(NSString *)labelText value:(NSString *)value {
    if (!value) {
        return;
    }
    
    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.distribution = NSStackViewDistributionFill;
    row.spacing = 8;
    
    NSTextField *label = [NSTextField labelWithString:labelText];
    label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    label.textColor = [Theme tertiaryTextColor];
    [label setContentHuggingPriority:NSLayoutPriorityDefaultHigh 
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    
    NSTextField *valueField = [NSTextField labelWithString:value];
    valueField.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    valueField.textColor = [Theme secondaryTextColor];
    valueField.alignment = NSTextAlignmentRight;
    valueField.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [valueField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow 
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
    
    [row addArrangedSubview:label];
    [row addArrangedSubview:valueField];
    
    [self.contentStack addArrangedSubview:row];
}

- (void)addSeparator {
    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStack addArrangedSubview:separator];
}

- (NSString *)formatDate:(NSDate *)date {
    return [DateFormatters displayStringFromDate:date];
}

@end

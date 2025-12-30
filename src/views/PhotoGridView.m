/**
 * PhotoGridView.m
 * Collection view based grid for photos
 */

#import "PhotoGridView.h"
#import "ThumbnailCache.h"
#import "../models/PhotoStore.h"
#import "../models/PhotoItem.h"
#import "../app/MainWindowController.h"
#import "../utils/Theme.h"

static NSString * const kCellIdentifier = @"PhotoCell";
static const CGFloat kThumbnailSize = 180.0;
static const CGFloat kSpacing = 4.0;

#pragma mark - Photo Cell

@interface PhotoGridCell : NSCollectionViewItem

@property (nonatomic, strong) NSImageView *thumbnailView;
@property (nonatomic, strong) NSProgressIndicator *loadingIndicator;
@property (nonatomic, copy) NSString *photoPath;

@end

@implementation PhotoGridCell

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kThumbnailSize, kThumbnailSize)];
    self.view.wantsLayer = YES;
    self.view.layer.cornerRadius = 8.0;
    self.view.layer.masksToBounds = YES;
    self.view.layer.backgroundColor = [Theme gridCellBackgroundColor].CGColor;
    
    /* Thumbnail image */
    self.thumbnailView = [[NSImageView alloc] initWithFrame:self.view.bounds];
    self.thumbnailView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.thumbnailView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.thumbnailView.wantsLayer = YES;
    [self.view addSubview:self.thumbnailView];
    
    /* Loading indicator */
    self.loadingIndicator = [[NSProgressIndicator alloc] init];
    self.loadingIndicator.style = NSProgressIndicatorStyleSpinning;
    self.loadingIndicator.controlSize = NSControlSizeSmall;
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.hidden = YES;
    [self.view addSubview:self.loadingIndicator];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.thumbnailView.image = nil;
    self.photoPath = nil;
    [self.loadingIndicator stopAnimation:nil];
    self.loadingIndicator.hidden = YES;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    
    if (selected) {
        self.view.layer.borderWidth = 3.0;
        self.view.layer.borderColor = [Theme selectionBorderColor].CGColor;
    } else {
        self.view.layer.borderWidth = 0;
    }
}

- (void)configureWithPhoto:(PhotoItem *)photo {
    NSString *path = photo.path;
    self.photoPath = path;
    
    /* Check cache first */
    ThumbnailCache *cache = [ThumbnailCache sharedCache];
    NSImage *cached = [cache thumbnailForPath:path];
    
    if (cached) {
        self.thumbnailView.image = cached;
        self.loadingIndicator.hidden = YES;
        return;
    }
    
    /* Show loading indicator */
    self.thumbnailView.image = nil;
    self.loadingIndicator.hidden = NO;
    [self.loadingIndicator startAnimation:nil];
    
    /* Request thumbnail generation */
    __weak typeof(self) weakSelf = self;
    [cache generateThumbnailForPath:path completion:^(NSImage *thumbnail) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        /* Verify still showing same photo */
        if ([strongSelf.photoPath isEqualToString:path]) {
            [strongSelf.loadingIndicator stopAnimation:nil];
            strongSelf.loadingIndicator.hidden = YES;
            strongSelf.thumbnailView.image = thumbnail;
        }
    }];
}

@end

#pragma mark - Grid View

@interface PhotoGridView () <NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout>

@property (nonatomic, weak, readwrite) PhotoStore *photoStore;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSCollectionView *collectionView;

@end

@implementation PhotoGridView

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
    
    /* Flow layout */
    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    layout.itemSize = NSMakeSize(kThumbnailSize, kThumbnailSize);
    layout.minimumInteritemSpacing = kSpacing;
    layout.minimumLineSpacing = kSpacing;
    layout.sectionInset = NSEdgeInsetsMake(16, 16, 16, 16);
    
    /* Collection view */
    self.collectionView = [[NSCollectionView alloc] initWithFrame:NSZeroRect];
    self.collectionView.collectionViewLayout = layout;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.backgroundColors = @[[NSColor clearColor]];
    self.collectionView.selectable = YES;
    self.collectionView.allowsMultipleSelection = NO;
    [self.collectionView registerClass:[PhotoGridCell class] forItemWithIdentifier:kCellIdentifier];
    
    /* Scroll view */
    self.scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.documentView = self.collectionView;
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.backgroundColor = [NSColor clearColor];
    self.scrollView.drawsBackground = NO;
    [self addSubview:self.scrollView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (void)reloadData {
    [self.collectionView reloadData];
    
    /* Select current photo */
    NSUInteger index = self.photoStore.selectedIndex;
    if (index < self.photoStore.photoCount) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:index inSection:0];
        [self.collectionView selectItemsAtIndexPaths:[NSSet setWithObject:indexPath]
                                      scrollPosition:NSCollectionViewScrollPositionCenteredVertically];
    }
    
    /* Start background preloading of all thumbnails */
    [self startBackgroundPreloading];
}

- (void)startBackgroundPreloading {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    
    for (NSUInteger i = 0; i < self.photoStore.photoCount; i++) {
        PhotoItem *photo = [self.photoStore photoAtIndex:i];
        if (photo) {
            [paths addObject:photo.path];
        }
    }
    
    [[ThumbnailCache sharedCache] preloadThumbnailsForPaths:paths];
}

#pragma mark - NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.photoStore.photoCount;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView 
                   itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    PhotoGridCell *cell = [collectionView makeItemWithIdentifier:kCellIdentifier forIndexPath:indexPath];
    
    PhotoItem *photo = [self.photoStore photoAtIndex:(NSUInteger)indexPath.item];
    if (photo) {
        [cell configureWithPhoto:photo];
    }
    
    return cell;
}

#pragma mark - NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (indexPath) {
        [self.photoStore selectIndex:(NSUInteger)indexPath.item];
        
        /* Switch to single view */
        MainWindowController *controller = (MainWindowController *)self.window.windowController;
        [controller toggleGridView:nil];
    }
}

@end

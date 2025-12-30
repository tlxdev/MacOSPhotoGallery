/**
 * PhotoGridView.m
 * Collection view based grid for photos with thumbnail caching and background preloading
 */

#import "PhotoGridView.h"
#import "ThumbnailCache.h"
#import "../models/PhotoStore.h"
#import "../models/PhotoItem.h"
#import "../app/MainWindowController.h"

static NSString * const kCellIdentifier = @"PhotoCell";
static const CGFloat kThumbnailSize = 180.0;
static const CGFloat kSpacing = 4.0;

#pragma mark - Thumbnail Cache Implementation

@interface ThumbnailCache ()
- (void)setThumbnail:(NSImage *)thumbnail forPath:(NSString *)path;
@end

@implementation ThumbnailCache {
    NSCache *_cache;
    NSMutableDictionary<NSString *, NSMutableArray *> *_pendingRequests;
    NSMutableSet<NSString *> *_inProgress;
    NSOperationQueue *_operationQueue;
    NSOperationQueue *_preloadQueue;
}

+ (instancetype)sharedCache {
    static ThumbnailCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[ThumbnailCache alloc] init];
    });
    return cache;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [[NSCache alloc] init];
        _cache.countLimit = 5000; /* Cache up to 5000 thumbnails */
        _cache.totalCostLimit = 500 * 1024 * 1024; /* 500MB limit */
        _pendingRequests = [NSMutableDictionary dictionary];
        _inProgress = [NSMutableSet set];
        
        /* High priority queue for visible thumbnails */
        _operationQueue = [[NSOperationQueue alloc] init];
        _operationQueue.maxConcurrentOperationCount = 4;
        _operationQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        _operationQueue.name = @"com.photoviewer.thumbnails";
        
        /* Low priority queue for background preloading */
        _preloadQueue = [[NSOperationQueue alloc] init];
        _preloadQueue.maxConcurrentOperationCount = 2; /* Lower concurrency for background */
        _preloadQueue.qualityOfService = NSQualityOfServiceBackground;
        _preloadQueue.name = @"com.photoviewer.preload";
    }
    return self;
}

- (NSImage *)thumbnailForPath:(NSString *)path {
    return [_cache objectForKey:path];
}

- (void)setThumbnail:(NSImage *)thumbnail forPath:(NSString *)path {
    if (thumbnail && path) {
        /* Store without cost tracking - let count limit handle eviction */
        [_cache setObject:thumbnail forKey:path];
    }
}

- (NSImage *)createThumbnailFromPath:(NSString *)path {
    if (!path) {
        return nil;
    }
    
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) {
        return nil;
    }
    
    CGFloat targetSize = kThumbnailSize * 2; /* Retina */
    
    /* Use ImageIO to create thumbnail - this downsamples at decode time,
       never loading the full image into memory */
    NSDictionary *options = @{
        (id)kCGImageSourceThumbnailMaxPixelSize: @(targetSize),
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES, /* Apply EXIF rotation */
        (id)kCGImageSourceShouldCacheImmediately: @YES
    };
    
    CGImageRef cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    
    if (!cgThumb) {
        return nil;
    }
    
    NSImage *thumbnail = [[NSImage alloc] initWithCGImage:cgThumb size:NSZeroSize];
    CGImageRelease(cgThumb);
    
    return thumbnail;
}

- (void)generateThumbnailForPath:(NSString *)path completion:(void (^)(NSImage *thumbnail))completion {
    /* Check cache first */
    NSImage *cached = [self thumbnailForPath:path];
    if (cached) {
        if (completion) {
            completion(cached);
        }
        return;
    }
    
    @synchronized (self) {
        /* Add to pending requests */
        NSMutableArray *pending = _pendingRequests[path];
        if (!pending) {
            pending = [NSMutableArray array];
            _pendingRequests[path] = pending;
        }
        if (completion) {
            [pending addObject:[completion copy]];
        }
        
        /* Already generating? */
        if ([_inProgress containsObject:path]) {
            return;
        }
        [_inProgress addObject:path];
    }
    
    /* Generate thumbnail with high priority */
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        NSImage *thumbnail = [self createThumbnailFromPath:path];
        
        if (thumbnail) {
            [self setThumbnail:thumbnail forPath:path];
        }
        
        /* Notify all pending requests */
        NSArray *completions;
        @synchronized (self) {
            completions = [self->_pendingRequests[path] copy];
            [self->_pendingRequests removeObjectForKey:path];
            [self->_inProgress removeObject:path];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            for (void (^block)(NSImage *) in completions) {
                block(thumbnail);
            }
        });
    }];
    
    operation.queuePriority = NSOperationQueuePriorityHigh;
    [_operationQueue addOperation:operation];
}

- (void)preloadThumbnailsForPaths:(NSArray<NSString *> *)paths {
    /* Cancel any existing preload operations */
    [_preloadQueue cancelAllOperations];
    
    for (NSString *path in paths) {
        /* Skip if already cached */
        if ([self thumbnailForPath:path]) {
            continue;
        }
        
        /* Skip if already being generated */
        @synchronized (self) {
            if ([_inProgress containsObject:path]) {
                continue;
            }
        }
        
        /* Add low-priority preload operation */
        NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
            /* Double-check cache (might have been generated since) */
            if ([self thumbnailForPath:path]) {
                return;
            }
            
            @synchronized (self) {
                if ([self->_inProgress containsObject:path]) {
                    return;
                }
                [self->_inProgress addObject:path];
            }
            
            NSImage *thumbnail = [self createThumbnailFromPath:path];
            
            if (thumbnail) {
                [self setThumbnail:thumbnail forPath:path];
            }
            
            @synchronized (self) {
                [self->_inProgress removeObject:path];
            }
        }];
        
        operation.queuePriority = NSOperationQueuePriorityLow;
        [_preloadQueue addOperation:operation];
    }
}

- (void)cancelPreloading {
    [_preloadQueue cancelAllOperations];
}

@end

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
    self.view.layer.backgroundColor = [NSColor colorWithWhite:0.12 alpha:1.0].CGColor;
    
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
        self.view.layer.borderColor = [NSColor colorWithRed:0.055 green:0.647 blue:0.914 alpha:1.0].CGColor;
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
    self.layer.backgroundColor = [NSColor colorWithRed:0.035 green:0.035 blue:0.043 alpha:1.0].CGColor;
    
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

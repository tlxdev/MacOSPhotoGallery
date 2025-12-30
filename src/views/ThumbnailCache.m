/**
 * ThumbnailCache.m
 * Singleton thumbnail cache with background preloading using ImageIO
 */

#import "ThumbnailCache.h"
#import <ImageIO/ImageIO.h>

static const CGFloat kThumbnailSize = 180.0;

@interface ThumbnailCache ()

@property (nonatomic, strong) NSCache *cache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *pendingRequests;
@property (nonatomic, strong) NSMutableSet<NSString *> *inProgress;
@property (nonatomic, strong) NSOperationQueue *operationQueue;
@property (nonatomic, strong) NSOperationQueue *preloadQueue;
@property (nonatomic, strong) dispatch_queue_t syncQueue;

@end

@implementation ThumbnailCache

#pragma mark - Singleton

+ (instancetype)sharedCache {
    static ThumbnailCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[ThumbnailCache alloc] init];
    });
    return cache;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [[NSCache alloc] init];
        _cache.countLimit = 5000;
        _cache.totalCostLimit = 500 * 1024 * 1024; /* 500MB */
        
        _pendingRequests = [NSMutableDictionary dictionary];
        _inProgress = [NSMutableSet set];
        
        /* Serial queue for thread-safe synchronization */
        _syncQueue = dispatch_queue_create("com.photoviewer.thumbnailcache.sync", DISPATCH_QUEUE_SERIAL);
        
        /* High priority queue for visible thumbnails */
        _operationQueue = [[NSOperationQueue alloc] init];
        _operationQueue.maxConcurrentOperationCount = 4;
        _operationQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        _operationQueue.name = @"com.photoviewer.thumbnails";
        
        /* Low priority queue for background preloading */
        _preloadQueue = [[NSOperationQueue alloc] init];
        _preloadQueue.maxConcurrentOperationCount = 2;
        _preloadQueue.qualityOfService = NSQualityOfServiceBackground;
        _preloadQueue.name = @"com.photoviewer.preload";
    }
    return self;
}

#pragma mark - Cache Access

- (NSImage *)thumbnailForPath:(NSString *)path {
    if (!path) {
        return nil;
    }
    return [self.cache objectForKey:path];
}

- (void)setThumbnail:(NSImage *)thumbnail forPath:(NSString *)path {
    if (thumbnail && path) {
        [self.cache setObject:thumbnail forKey:path];
    }
}

#pragma mark - Thumbnail Generation

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
    
    /* Use ImageIO to create thumbnail - downsamples at decode time */
    NSDictionary *options = @{
        (id)kCGImageSourceThumbnailMaxPixelSize: @(targetSize),
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
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
    if (!path) {
        if (completion) {
            completion(nil);
        }
        return;
    }
    
    /* Check cache first */
    NSImage *cached = [self thumbnailForPath:path];
    if (cached) {
        if (completion) {
            completion(cached);
        }
        return;
    }
    
    __block BOOL shouldGenerate = NO;
    
    dispatch_sync(self.syncQueue, ^{
        /* Add to pending requests */
        NSMutableArray *pending = self.pendingRequests[path];
        if (!pending) {
            pending = [NSMutableArray array];
            self.pendingRequests[path] = pending;
        }
        if (completion) {
            [pending addObject:[completion copy]];
        }
        
        /* Check if already generating */
        if (![self.inProgress containsObject:path]) {
            [self.inProgress addObject:path];
            shouldGenerate = YES;
        }
    });
    
    if (!shouldGenerate) {
        return;
    }
    
    /* Generate thumbnail with high priority */
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        NSImage *thumbnail = [self createThumbnailFromPath:path];
        
        if (thumbnail) {
            [self setThumbnail:thumbnail forPath:path];
        }
        
        /* Notify all pending requests */
        __block NSArray *completions = nil;
        dispatch_sync(self.syncQueue, ^{
            completions = [self.pendingRequests[path] copy];
            [self.pendingRequests removeObjectForKey:path];
            [self.inProgress removeObject:path];
        });
        
        dispatch_async(dispatch_get_main_queue(), ^{
            for (void (^block)(NSImage *) in completions) {
                block(thumbnail);
            }
        });
    }];
    
    operation.queuePriority = NSOperationQueuePriorityHigh;
    [self.operationQueue addOperation:operation];
}

#pragma mark - Preloading

- (void)preloadThumbnailsForPaths:(NSArray<NSString *> *)paths {
    [self.preloadQueue cancelAllOperations];
    
    for (NSString *path in paths) {
        if (!path) {
            continue;
        }
        
        /* Skip if already cached */
        if ([self thumbnailForPath:path]) {
            continue;
        }
        
        /* Skip if already being generated */
        __block BOOL isInProgress = NO;
        dispatch_sync(self.syncQueue, ^{
            isInProgress = [self.inProgress containsObject:path];
        });
        
        if (isInProgress) {
            continue;
        }
        
        /* Add low-priority preload operation */
        NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
            /* Double-check cache */
            if ([self thumbnailForPath:path]) {
                return;
            }
            
            __block BOOL shouldGenerate = NO;
            dispatch_sync(self.syncQueue, ^{
                if (![self.inProgress containsObject:path]) {
                    [self.inProgress addObject:path];
                    shouldGenerate = YES;
                }
            });
            
            if (!shouldGenerate) {
                return;
            }
            
            NSImage *thumbnail = [self createThumbnailFromPath:path];
            
            if (thumbnail) {
                [self setThumbnail:thumbnail forPath:path];
            }
            
            dispatch_sync(self.syncQueue, ^{
                [self.inProgress removeObject:path];
            });
        }];
        
        operation.queuePriority = NSOperationQueuePriorityLow;
        [self.preloadQueue addOperation:operation];
    }
}

- (void)cancelPreloading {
    [self.preloadQueue cancelAllOperations];
}

#pragma mark - Cache Management

- (void)clearCache {
    [self.cache removeAllObjects];
}

- (void)removeThumbnailForPath:(NSString *)path {
    if (path) {
        [self.cache removeObjectForKey:path];
    }
}

@end


/**
 * PhotoStore.m
 * Photo store implementation with FSEvents folder watching and input validation
 */

#import "PhotoStore.h"
#import "PhotoItem.h"
#import "../core/photo_scanner.h"
#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>

NSErrorDomain const PhotoStoreErrorDomain = @"PhotoStoreErrorDomain";

/* Forward declaration for FSEvents callback */
@interface PhotoStore ()
- (void)handleFolderChange;
@end

/* FSEvents callback context */
typedef struct {
    void *photoStore; /* __bridge to PhotoStore */
} FSEventContext;

/* FSEvents callback function */
static void fsEventsCallback(
    ConstFSEventStreamRef streamRef,
    void *clientCallBackInfo,
    size_t numEvents,
    void *eventPaths,
    const FSEventStreamEventFlags eventFlags[],
    const FSEventStreamEventId eventIds[]
) {
    (void)streamRef;
    (void)numEvents;
    (void)eventPaths;
    (void)eventFlags;
    (void)eventIds;
    
    FSEventContext *context = (FSEventContext *)clientCallBackInfo;
    PhotoStore *store = (__bridge PhotoStore *)context->photoStore;
    
    /* Notify on main thread */
    dispatch_async(dispatch_get_main_queue(), ^{
        [store handleFolderChange];
    });
}

@interface PhotoStore ()

@property (nonatomic, assign, readwrite) NSUInteger selectedIndex;
@property (nonatomic, copy, readwrite, nullable) NSString *folderPath;
@property (nonatomic, assign, readwrite, getter=isScanning) BOOL scanning;
@property (nonatomic, assign, readwrite, getter=isWatching) BOOL watching;

@property (nonatomic, strong) NSMutableArray<PhotoItem *> *photos;
@property (nonatomic, strong) dispatch_queue_t scanQueue;
@property (nonatomic, strong) NSCache *imageCache;

/* FSEvents */
@property (nonatomic, assign) FSEventStreamRef eventStream;
@property (nonatomic, assign) FSEventContext *eventContext;
@property (nonatomic, strong) dispatch_queue_t fsEventsQueue;

/* Debounce timer for folder changes */
@property (nonatomic, strong) NSTimer *debounceTimer;

@end

@implementation PhotoStore

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _photos = [NSMutableArray array];
        _selectedIndex = 0;
        _scanQueue = dispatch_queue_create("com.photoviewer.scan", DISPATCH_QUEUE_SERIAL);
        _imageCache = [[NSCache alloc] init];
        _imageCache.countLimit = 20;
        _eventStream = NULL;
        _eventContext = NULL;
        _fsEventsQueue = dispatch_queue_create("com.photoviewer.fsevents", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self stopWatchingFolder];
}

#pragma mark - Properties

- (NSUInteger)photoCount {
    return self.photos.count;
}

- (NSString *)folderName {
    return self.folderPath.lastPathComponent;
}

#pragma mark - Input Validation

- (BOOL)validateFolderPath:(NSString *)path error:(NSError **)error {
    /* Check for nil or empty path */
    if (!path || path.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PhotoStoreErrorDomain
                                         code:PhotoStoreErrorCodeInvalidPath
                                     userInfo:@{NSLocalizedDescriptionKey: @"Path cannot be empty"}];
        }
        return NO;
    }
    
    /* Normalize path and resolve symlinks */
    NSString *normalizedPath = path.stringByStandardizingPath;
    NSString *resolvedPath = normalizedPath.stringByResolvingSymlinksInPath;
    
    /* Check for path traversal attempts */
    if ([normalizedPath containsString:@".."] || [path containsString:@".."]) {
        if (error) {
            *error = [NSError errorWithDomain:PhotoStoreErrorDomain
                                         code:PhotoStoreErrorCodePathTraversal
                                     userInfo:@{NSLocalizedDescriptionKey: @"Path contains invalid traversal sequences"}];
        }
        return NO;
    }
    
    /* Check path exists and is a directory */
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    BOOL exists = [fm fileExistsAtPath:resolvedPath isDirectory:&isDirectory];
    
    if (!exists) {
        if (error) {
            *error = [NSError errorWithDomain:PhotoStoreErrorDomain
                                         code:PhotoStoreErrorCodeInvalidPath
                                     userInfo:@{NSLocalizedDescriptionKey: @"Path does not exist"}];
        }
        return NO;
    }
    
    if (!isDirectory) {
        if (error) {
            *error = [NSError errorWithDomain:PhotoStoreErrorDomain
                                         code:PhotoStoreErrorCodePathNotDirectory
                                     userInfo:@{NSLocalizedDescriptionKey: @"Path is not a directory"}];
        }
        return NO;
    }
    
    /* Check read permission */
    if (![fm isReadableFileAtPath:resolvedPath]) {
        if (error) {
            *error = [NSError errorWithDomain:PhotoStoreErrorDomain
                                         code:PhotoStoreErrorCodePathNotReadable
                                     userInfo:@{NSLocalizedDescriptionKey: @"Directory is not readable"}];
        }
        return NO;
    }
    
    /* Validate path doesn't point to sensitive system directories */
    NSArray *forbiddenPrefixes = @[
        @"/System",
        @"/usr",
        @"/bin",
        @"/sbin",
        @"/var",
        @"/private/var",
        @"/Library/Caches",
        @"/Library/Logs"
    ];
    
    for (NSString *prefix in forbiddenPrefixes) {
        if ([resolvedPath hasPrefix:prefix]) {
            if (error) {
                *error = [NSError errorWithDomain:PhotoStoreErrorDomain
                                             code:PhotoStoreErrorCodeInvalidPath
                                         userInfo:@{NSLocalizedDescriptionKey: @"Cannot access system directories"}];
            }
            return NO;
        }
    }
    
    return YES;
}

#pragma mark - Directory Scanning

- (BOOL)scanDirectory:(NSString *)path {
    /* Validate path first */
    NSError *validationError = nil;
    if (![self validateFolderPath:path error:&validationError]) {
        if (self.onError) {
            self.onError(validationError);
        }
        return NO;
    }
    
    if (self.scanning) {
        return NO;
    }
    
    /* Stop watching old folder */
    [self stopWatchingFolder];
    
    self.scanning = YES;
    
    /* Resolve to canonical path */
    NSString *resolvedPath = path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    self.folderPath = resolvedPath;
    
    dispatch_async(self.scanQueue, ^{
        pv_photo_collection_t *collection = pv_collection_create();
        if (collection == NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.scanning = NO;
                if (self.onError) {
                    NSError *error = [NSError errorWithDomain:PhotoStoreErrorDomain
                                                         code:PhotoStoreErrorCodeScanFailed
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create photo collection"}];
                    self.onError(error);
                }
            });
            return;
        }
        
        int count = pv_scan_directory(collection, resolvedPath.UTF8String);
        
        NSMutableArray<PhotoItem *> *newPhotos = [NSMutableArray arrayWithCapacity:(NSUInteger)MAX(count, 0)];
        
        for (size_t i = 0; i < collection->count; i++) {
            const pv_photo_t *photo = pv_collection_get(collection, i);
            if (photo) {
                PhotoItem *item = [[PhotoItem alloc] initWithPath:@(photo->path)
                                                             name:@(photo->name)
                                                         fileSize:photo->size
                                                      createdDate:[NSDate dateWithTimeIntervalSince1970:photo->created_time]
                                                     modifiedDate:[NSDate dateWithTimeIntervalSince1970:photo->modified_time]];
                item.index = i;
                [newPhotos addObject:item];
            }
        }
        
        pv_collection_free(collection);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.photos removeAllObjects];
            [self.photos addObjectsFromArray:newPhotos];
            self.selectedIndex = 0;
            self.scanning = NO;
            
            /* Start watching folder for changes */
            [self startWatchingFolder];
            
            if (self.onPhotosLoaded) {
                self.onPhotosLoaded(self.photos.count);
            }
            
            if (self.photos.count > 0 && self.onSelectionChanged) {
                self.onSelectionChanged(0);
            }
        });
    });
    
    return YES;
}

#pragma mark - Navigation

- (void)selectIndex:(NSUInteger)index {
    if (index >= self.photos.count) {
        return;
    }
    
    if (index != self.selectedIndex) {
        self.selectedIndex = index;
        
        if (self.onSelectionChanged) {
            self.onSelectionChanged(index);
        }
        
        [self preloadAdjacentPhotos];
    }
}

- (void)selectNext {
    if (self.selectedIndex < self.photos.count - 1) {
        [self selectIndex:self.selectedIndex + 1];
    }
}

- (void)selectPrevious {
    if (self.selectedIndex > 0) {
        [self selectIndex:self.selectedIndex - 1];
    }
}

#pragma mark - Photo Access

- (PhotoItem *)currentPhoto {
    return [self photoAtIndex:self.selectedIndex];
}

- (PhotoItem *)photoAtIndex:(NSUInteger)index {
    if (index >= self.photos.count) {
        return nil;
    }
    return self.photos[index];
}

#pragma mark - Preloading

- (void)preloadAdjacentPhotos {
    static const NSInteger kPreloadCount = 3;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        for (NSInteger offset = -kPreloadCount; offset <= kPreloadCount; offset++) {
            if (offset == 0) {
                continue;
            }
            
            NSInteger index = (NSInteger)self.selectedIndex + offset;
            if (index >= 0 && (NSUInteger)index < self.photos.count) {
                PhotoItem *photo = self.photos[(NSUInteger)index];
                
                /* Check if already cached */
                if ([self.imageCache objectForKey:photo.path]) {
                    continue;
                }
                
                /* Preload image */
                NSURL *url = [NSURL fileURLWithPath:photo.path];
                NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
                if (image) {
                    [self.imageCache setObject:image forKey:photo.path];
                }
            }
        }
    });
}

- (NSImage *)cachedImageForPath:(NSString *)path {
    return [self.imageCache objectForKey:path];
}

- (void)cacheImage:(NSImage *)image forPath:(NSString *)path {
    [self.imageCache setObject:image forKey:path];
}

#pragma mark - FSEvents Folder Watching

- (void)startWatchingFolder {
    if (!self.folderPath || self.watching) {
        return;
    }
    
    /* Create context */
    self.eventContext = malloc(sizeof(FSEventContext));
    if (!self.eventContext) {
        return;
    }
    self.eventContext->photoStore = (__bridge void *)self;
    
    /* Setup FSEvents stream context */
    FSEventStreamContext streamContext = {
        .version = 0,
        .info = self.eventContext,
        .retain = NULL,
        .release = NULL,
        .copyDescription = NULL
    };
    
    /* Create paths array */
    CFArrayRef pathsToWatch = (__bridge CFArrayRef)@[self.folderPath];
    
    /* Create event stream */
    self.eventStream = FSEventStreamCreate(
        kCFAllocatorDefault,
        &fsEventsCallback,
        &streamContext,
        pathsToWatch,
        kFSEventStreamEventIdSinceNow,
        1.0, /* Latency in seconds */
        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
    );
    
    if (self.eventStream) {
        FSEventStreamSetDispatchQueue(self.eventStream, self.fsEventsQueue);
        FSEventStreamStart(self.eventStream);
        self.watching = YES;
    } else {
        free(self.eventContext);
        self.eventContext = NULL;
    }
}

- (void)stopWatchingFolder {
    if (self.eventStream) {
        FSEventStreamStop(self.eventStream);
        FSEventStreamInvalidate(self.eventStream);
        FSEventStreamRelease(self.eventStream);
        self.eventStream = NULL;
    }
    
    if (self.eventContext) {
        free(self.eventContext);
        self.eventContext = NULL;
    }
    
    [self.debounceTimer invalidate];
    self.debounceTimer = nil;
    
    self.watching = NO;
}

- (void)handleFolderChange {
    /* Debounce rapid changes (e.g., batch file operations) */
    [self.debounceTimer invalidate];
    
    self.debounceTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                          target:self
                                                        selector:@selector(debouncedFolderChange)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)debouncedFolderChange {
    self.debounceTimer = nil;
    
    /* Notify delegate */
    if (self.onFolderChanged) {
        self.onFolderChanged();
    }
}

- (void)rescanCurrentFolder {
    if (self.folderPath && !self.scanning) {
        /* Remember current selection */
        PhotoItem *currentPhoto = [self currentPhoto];
        NSString *currentPath = currentPhoto.path;
        
        /* Stop watching during rescan */
        [self stopWatchingFolder];
        
        self.scanning = YES;
        NSString *path = self.folderPath;
        
        dispatch_async(self.scanQueue, ^{
            pv_photo_collection_t *collection = pv_collection_create();
            if (collection == NULL) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.scanning = NO;
                    [self startWatchingFolder];
                });
                return;
            }
            
            pv_scan_directory(collection, path.UTF8String);
            
            NSMutableArray<PhotoItem *> *newPhotos = [NSMutableArray arrayWithCapacity:collection->count];
            NSUInteger newSelectedIndex = 0;
            
            for (size_t i = 0; i < collection->count; i++) {
                const pv_photo_t *photo = pv_collection_get(collection, i);
                if (photo) {
                    PhotoItem *item = [[PhotoItem alloc] initWithPath:@(photo->path)
                                                                 name:@(photo->name)
                                                             fileSize:photo->size
                                                          createdDate:[NSDate dateWithTimeIntervalSince1970:photo->created_time]
                                                         modifiedDate:[NSDate dateWithTimeIntervalSince1970:photo->modified_time]];
                    item.index = i;
                    [newPhotos addObject:item];
                    
                    /* Try to maintain selection */
                    if (currentPath && [item.path isEqualToString:currentPath]) {
                        newSelectedIndex = i;
                    }
                }
            }
            
            pv_collection_free(collection);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.photos removeAllObjects];
                [self.photos addObjectsFromArray:newPhotos];
                
                /* Restore selection or clamp to bounds */
                if (newSelectedIndex < self.photos.count) {
                    self.selectedIndex = newSelectedIndex;
                } else if (self.photos.count > 0) {
                    self.selectedIndex = self.photos.count - 1;
                } else {
                    self.selectedIndex = 0;
                }
                
                self.scanning = NO;
                
                /* Restart watching */
                [self startWatchingFolder];
                
                if (self.onPhotosLoaded) {
                    self.onPhotosLoaded(self.photos.count);
                }
            });
        });
    }
}

@end

/**
 * PhotoStore.m
 * Photo store implementation using core C library
 */

#import "PhotoStore.h"
#import "PhotoItem.h"
#import "../core/photo_scanner.h"
#import <Cocoa/Cocoa.h>

@interface PhotoStore ()

@property (nonatomic, assign, readwrite) NSUInteger selectedIndex;
@property (nonatomic, copy, readwrite, nullable) NSString *folderPath;
@property (nonatomic, assign, readwrite, getter=isScanning) BOOL scanning;

@property (nonatomic, strong) NSMutableArray<PhotoItem *> *photos;
@property (nonatomic, strong) dispatch_queue_t scanQueue;
@property (nonatomic, strong) NSCache *imageCache;

@end

@implementation PhotoStore

- (instancetype)init {
    self = [super init];
    if (self) {
        _photos = [NSMutableArray array];
        _selectedIndex = 0;
        _scanQueue = dispatch_queue_create("com.photoviewer.scan", DISPATCH_QUEUE_SERIAL);
        _imageCache = [[NSCache alloc] init];
        _imageCache.countLimit = 20;
    }
    return self;
}

#pragma mark - Properties

- (NSUInteger)photoCount {
    return self.photos.count;
}

- (NSString *)folderName {
    return self.folderPath.lastPathComponent;
}

#pragma mark - Directory Scanning

- (void)scanDirectory:(NSString *)path {
    if (self.scanning) {
        return;
    }
    
    self.scanning = YES;
    self.folderPath = path;
    
    dispatch_async(self.scanQueue, ^{
        pv_photo_collection_t *collection = pv_collection_create();
        if (collection == NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.scanning = NO;
            });
            return;
        }
        
        int count = pv_scan_directory(collection, path.UTF8String);
        
        NSMutableArray<PhotoItem *> *newPhotos = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
        
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
            
            if (self.onPhotosLoaded) {
                self.onPhotosLoaded(self.photos.count);
            }
            
            if (self.photos.count > 0 && self.onSelectionChanged) {
                self.onSelectionChanged(0);
            }
        });
    });
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

@end


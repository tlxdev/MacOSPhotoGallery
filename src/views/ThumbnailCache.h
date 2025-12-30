/**
 * ThumbnailCache.h
 * Singleton thumbnail cache with background preloading
 */

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface ThumbnailCache : NSObject

+ (instancetype)sharedCache;

/* Get cached thumbnail (returns nil if not cached) */
- (nullable NSImage *)thumbnailForPath:(NSString *)path;

/* Generate thumbnail with completion callback */
- (void)generateThumbnailForPath:(NSString *)path 
                      completion:(nullable void (^)(NSImage * _Nullable thumbnail))completion;

/* Preload thumbnails in background (low priority) */
- (void)preloadThumbnailsForPaths:(NSArray<NSString *> *)paths;

/* Cancel background preloading */
- (void)cancelPreloading;

@end

NS_ASSUME_NONNULL_END


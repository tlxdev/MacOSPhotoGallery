/**
 * ThumbnailCache.h
 * Singleton thumbnail cache with background preloading
 */

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface ThumbnailCache : NSObject

/**
 * Shared singleton instance
 */
+ (instancetype)sharedCache;

/**
 * Get cached thumbnail (returns nil if not cached)
 * @param path Full path to the image file
 * @return Cached thumbnail or nil
 */
- (nullable NSImage *)thumbnailForPath:(NSString *)path;

/**
 * Generate thumbnail with completion callback
 * If cached, returns immediately via callback
 * Otherwise generates asynchronously on a background queue
 * @param path Full path to the image file
 * @param completion Called on main thread with thumbnail (or nil on failure)
 */
- (void)generateThumbnailForPath:(NSString *)path 
                      completion:(nullable void (^)(NSImage * _Nullable thumbnail))completion;

/**
 * Preload thumbnails in background (low priority)
 * Cancels any existing preload operations
 * @param paths Array of file paths to preload
 */
- (void)preloadThumbnailsForPaths:(NSArray<NSString *> *)paths;

/**
 * Cancel all background preloading operations
 */
- (void)cancelPreloading;

/**
 * Clear all cached thumbnails
 */
- (void)clearCache;

/**
 * Remove a specific thumbnail from cache
 * @param path Path of thumbnail to remove
 */
- (void)removeThumbnailForPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END

/**
 * RecentsManager.h
 * Manages recently opened folders with persistence
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const RecentsDidChangeNotification;

@interface RecentsManager : NSObject

/**
 * Shared singleton instance
 */
+ (instancetype)sharedManager;

/**
 * Array of recent folder paths (newest first)
 */
@property (nonatomic, readonly) NSArray<NSString *> *recentFolders;

/**
 * Maximum number of recent folders to keep
 */
@property (nonatomic, assign) NSUInteger maxRecents;

/**
 * Add a folder to recents (moves to top if already exists)
 * @param path Folder path to add
 */
- (void)addRecentFolder:(NSString *)path;

/**
 * Remove a folder from recents
 * @param path Folder path to remove
 */
- (void)removeRecentFolder:(NSString *)path;

/**
 * Clear all recent folders
 */
- (void)clearRecents;

/**
 * Get display name for a folder path
 * @param path Full folder path
 * @return Folder name for display
 */
- (NSString *)displayNameForPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END


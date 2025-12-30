/**
 * PhotoStore.h
 * Central store for photo collection and selection state
 * Includes FSEvents folder watching for live updates
 */

#import <Foundation/Foundation.h>

@class PhotoItem;

NS_ASSUME_NONNULL_BEGIN

/* Validation error domain */
extern NSErrorDomain const PhotoStoreErrorDomain;

typedef NS_ENUM(NSInteger, PhotoStoreErrorCode) {
    PhotoStoreErrorCodeInvalidPath = 1,
    PhotoStoreErrorCodePathNotDirectory,
    PhotoStoreErrorCodePathNotReadable,
    PhotoStoreErrorCodePathTraversal,
    PhotoStoreErrorCodeScanFailed
};

typedef void (^PhotoStoreSelectionChangedBlock)(NSUInteger index);
typedef void (^PhotoStorePhotosLoadedBlock)(NSUInteger count);
typedef void (^PhotoStoreErrorBlock)(NSError *error);
typedef void (^PhotoStoreFolderChangedBlock)(void);

@interface PhotoStore : NSObject

@property (nonatomic, assign, readonly) NSUInteger photoCount;
@property (nonatomic, assign, readonly) NSUInteger selectedIndex;
@property (nonatomic, copy, readonly, nullable) NSString *folderPath;
@property (nonatomic, copy, readonly, nullable) NSString *folderName;
@property (nonatomic, assign, readonly, getter=isScanning) BOOL scanning;
@property (nonatomic, assign, readonly, getter=isWatching) BOOL watching;

/* Callbacks */
@property (nonatomic, copy, nullable) PhotoStoreSelectionChangedBlock onSelectionChanged;
@property (nonatomic, copy, nullable) PhotoStorePhotosLoadedBlock onPhotosLoaded;
@property (nonatomic, copy, nullable) PhotoStoreErrorBlock onError;
@property (nonatomic, copy, nullable) PhotoStoreFolderChangedBlock onFolderChanged;

/**
 * Scan a directory for photos with validation
 * @param path Directory path to scan
 * @return YES if scan started, NO if validation failed (check onError callback)
 */
- (BOOL)scanDirectory:(NSString *)path;

/**
 * Validate a folder path without scanning
 * @param path Path to validate
 * @param error Populated with validation error if returns NO
 * @return YES if path is valid and safe
 */
- (BOOL)validateFolderPath:(NSString *)path error:(NSError **)error;

/* Navigation */
- (void)selectIndex:(NSUInteger)index;
- (void)selectNext;
- (void)selectPrevious;

/* Photo access */
- (nullable PhotoItem *)currentPhoto;
- (nullable PhotoItem *)photoAtIndex:(NSUInteger)index;

/* Preloading */
- (void)preloadAdjacentPhotos;

/* Folder watching */
- (void)startWatchingFolder;
- (void)stopWatchingFolder;
- (void)rescanCurrentFolder;

@end

NS_ASSUME_NONNULL_END

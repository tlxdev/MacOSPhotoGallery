/**
 * PhotoStore.h
 * Central store for photo collection and selection state
 */

#import <Foundation/Foundation.h>

@class PhotoItem;

NS_ASSUME_NONNULL_BEGIN

typedef void (^PhotoStoreSelectionChangedBlock)(NSUInteger index);
typedef void (^PhotoStorePhotosLoadedBlock)(NSUInteger count);

@interface PhotoStore : NSObject

@property (nonatomic, assign, readonly) NSUInteger photoCount;
@property (nonatomic, assign, readonly) NSUInteger selectedIndex;
@property (nonatomic, copy, readonly, nullable) NSString *folderPath;
@property (nonatomic, copy, readonly, nullable) NSString *folderName;
@property (nonatomic, assign, readonly, getter=isScanning) BOOL scanning;

/* Callbacks */
@property (nonatomic, copy, nullable) PhotoStoreSelectionChangedBlock onSelectionChanged;
@property (nonatomic, copy, nullable) PhotoStorePhotosLoadedBlock onPhotosLoaded;

/* Directory scanning */
- (void)scanDirectory:(NSString *)path;

/* Navigation */
- (void)selectIndex:(NSUInteger)index;
- (void)selectNext;
- (void)selectPrevious;

/* Photo access */
- (nullable PhotoItem *)currentPhoto;
- (nullable PhotoItem *)photoAtIndex:(NSUInteger)index;

/* Preloading */
- (void)preloadAdjacentPhotos;

@end

NS_ASSUME_NONNULL_END


/**
 * PhotoItem.h
 * Model representing a single photo
 */

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface PhotoItem : NSObject

@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, assign, readonly) uint64_t fileSize;
@property (nonatomic, strong, readonly) NSDate *createdDate;
@property (nonatomic, strong, readonly) NSDate *modifiedDate;
@property (nonatomic, assign) NSUInteger index;

/* Metadata (loaded on demand) */
@property (nonatomic, assign, readonly) CGSize dimensions;
@property (nonatomic, copy, readonly, nullable) NSString *cameraMake;
@property (nonatomic, copy, readonly, nullable) NSString *cameraModel;
@property (nonatomic, copy, readonly, nullable) NSString *exposureTime;
@property (nonatomic, copy, readonly, nullable) NSString *fNumber;
@property (nonatomic, copy, readonly, nullable) NSNumber *iso;
@property (nonatomic, copy, readonly, nullable) NSString *focalLength;
@property (nonatomic, copy, readonly, nullable) NSDate *dateTaken;
@property (nonatomic, copy, readonly, nullable) NSString *colorSpace;
@property (nonatomic, assign, readonly) BOOL metadataLoaded;

- (instancetype)initWithPath:(NSString *)path
                        name:(NSString *)name
                    fileSize:(uint64_t)fileSize
                 createdDate:(NSDate *)createdDate
                modifiedDate:(NSDate *)modifiedDate;

- (void)loadMetadata;

+ (NSString *)formattedFileSize:(uint64_t)bytes;

@end

NS_ASSUME_NONNULL_END


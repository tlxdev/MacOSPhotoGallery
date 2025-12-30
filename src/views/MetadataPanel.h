/**
 * MetadataPanel.h
 * Side panel displaying photo metadata and EXIF information
 */

#import <Cocoa/Cocoa.h>

@class PhotoStore;

NS_ASSUME_NONNULL_BEGIN

@interface MetadataPanel : NSView

@property (nonatomic, weak, readonly) PhotoStore *photoStore;

- (instancetype)initWithPhotoStore:(PhotoStore *)photoStore;
- (void)refresh;

@end

NS_ASSUME_NONNULL_END


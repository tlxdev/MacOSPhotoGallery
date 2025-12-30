/**
 * PhotoView.h
 * Main photo display view with zoom and pan support
 */

#import <Cocoa/Cocoa.h>

@class PhotoStore;

NS_ASSUME_NONNULL_BEGIN

@interface PhotoView : NSView

@property (nonatomic, weak, readonly) PhotoStore *photoStore;

- (instancetype)initWithPhotoStore:(PhotoStore *)photoStore;

- (void)displayCurrentPhoto;
- (void)zoomIn;
- (void)zoomOut;
- (void)zoomToActualSize;
- (void)zoomToFit;

@end

NS_ASSUME_NONNULL_END


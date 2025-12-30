/**
 * PhotoGridView.h
 * Virtualized grid view for browsing large photo collections
 */

#import <Cocoa/Cocoa.h>

@class PhotoStore;

NS_ASSUME_NONNULL_BEGIN

@interface PhotoGridView : NSView

@property (nonatomic, weak, readonly) PhotoStore *photoStore;

- (instancetype)initWithPhotoStore:(PhotoStore *)photoStore;
- (void)reloadData;

@end

NS_ASSUME_NONNULL_END


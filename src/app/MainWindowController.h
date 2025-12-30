/**
 * MainWindowController.h
 * Main window controller managing the photo viewer interface
 */

#import <Cocoa/Cocoa.h>

@class PhotoStore;
@class PhotoView;
@class PhotoGridView;
@class MetadataPanel;
@class ToolbarView;

@interface MainWindowController : NSWindowController <NSWindowDelegate>

@property (nonatomic, strong, readonly) PhotoStore *photoStore;
@property (nonatomic, assign, readonly) BOOL isGridViewVisible;
@property (nonatomic, assign, readonly) BOOL isMetadataVisible;

/* Actions */
- (void)openFolder:(id)sender;
- (void)openFolderAtPath:(NSString *)path;
- (void)toggleGridView:(id)sender;
- (void)toggleMetadata:(id)sender;
- (void)previousPhoto:(id)sender;
- (void)nextPhoto:(id)sender;
- (void)zoomIn:(id)sender;
- (void)zoomOut:(id)sender;
- (void)zoomToActualSize:(id)sender;
- (void)zoomToFit:(id)sender;
- (void)shareCurrentPhoto:(id)sender;
- (void)showInFinder:(id)sender;
- (void)copyCurrentPhoto:(id)sender;

@end


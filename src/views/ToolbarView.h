/**
 * ToolbarView.h
 * Top toolbar with navigation and actions
 */

#import <Cocoa/Cocoa.h>

@class MainWindowController;

NS_ASSUME_NONNULL_BEGIN

@interface ToolbarView : NSView

- (instancetype)initWithController:(MainWindowController *)controller;

- (void)updateForPhoto;
- (void)updateForViewMode;
- (void)updateForMetadataVisibility;

@end

NS_ASSUME_NONNULL_END


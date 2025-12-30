/**
 * AppDelegate.h
 * Application delegate handling lifecycle and menus
 */

#import <Cocoa/Cocoa.h>

@class MainWindowController;

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, strong, readonly) MainWindowController *mainWindowController;

- (void)openFolder:(id)sender;

@end


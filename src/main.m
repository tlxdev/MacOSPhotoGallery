/**
 * main.m
 * Application entry point
 */

#import <Cocoa/Cocoa.h>
#import "app/AppDelegate.h"

int main(int argc __attribute__((unused)), const char *argv[] __attribute__((unused))) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app activateIgnoringOtherApps:YES];
        
        [app run];
    }
    return 0;
}


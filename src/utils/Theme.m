/**
 * Theme.m
 * Centralized color and styling implementation
 */

#import "Theme.h"

@implementation Theme

#pragma mark - Background Colors

+ (NSColor *)backgroundColor {
    static NSColor *color = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [NSColor colorWithRed:0.035 green:0.035 blue:0.043 alpha:1.0];
    });
    return color;
}

+ (NSColor *)secondaryBackgroundColor {
    static NSColor *color = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [NSColor colorWithRed:0.075 green:0.075 blue:0.085 alpha:1.0];
    });
    return color;
}

+ (NSColor *)panelBackgroundColor {
    static NSColor *color = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [NSColor colorWithRed:0.075 green:0.075 blue:0.085 alpha:1.0];
    });
    return color;
}

#pragma mark - Text Colors

+ (NSColor *)textColor {
    static NSColor *color = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [NSColor colorWithWhite:0.95 alpha:1.0];
    });
    return color;
}

+ (NSColor *)secondaryTextColor {
    static NSColor *color = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [NSColor colorWithWhite:0.7 alpha:1.0];
    });
    return color;
}

+ (NSColor *)tertiaryTextColor {
    static NSColor *color = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [NSColor colorWithWhite:0.5 alpha:1.0];
    });
    return color;
}

#pragma mark - Accent Colors

+ (NSColor *)accentColor {
    static NSColor *color = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [NSColor colorWithRed:0.055 green:0.647 blue:0.914 alpha:1.0];
    });
    return color;
}

#pragma mark - UI Element Colors

+ (NSColor *)buttonTintColor {
    static NSColor *color = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [NSColor colorWithWhite:0.7 alpha:1.0];
    });
    return color;
}

+ (NSColor *)selectionBorderColor {
    return [self accentColor];
}

+ (NSColor *)gridCellBackgroundColor {
    static NSColor *color = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [NSColor colorWithWhite:0.12 alpha:1.0];
    });
    return color;
}

#pragma mark - CGColor Accessors

+ (CGColorRef)backgroundCGColor {
    return [self backgroundColor].CGColor;
}

+ (CGColorRef)secondaryBackgroundCGColor {
    return [self secondaryBackgroundColor].CGColor;
}

+ (CGColorRef)panelBackgroundCGColor {
    return [self panelBackgroundColor].CGColor;
}

@end


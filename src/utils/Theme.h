/**
 * Theme.h
 * Centralized color and styling constants
 */

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface Theme : NSObject

#pragma mark - Background Colors

/** Primary background color (darkest) */
+ (NSColor *)backgroundColor;

/** Secondary background color (slightly lighter) */
+ (NSColor *)secondaryBackgroundColor;

/** Panel background color */
+ (NSColor *)panelBackgroundColor;

#pragma mark - Text Colors

/** Primary text color */
+ (NSColor *)textColor;

/** Secondary/muted text color */
+ (NSColor *)secondaryTextColor;

/** Tertiary/dimmed text color */
+ (NSColor *)tertiaryTextColor;

#pragma mark - Accent Colors

/** Primary accent color (blue) */
+ (NSColor *)accentColor;

#pragma mark - UI Element Colors

/** Button tint color */
+ (NSColor *)buttonTintColor;

/** Selected item border color */
+ (NSColor *)selectionBorderColor;

/** Grid cell background color */
+ (NSColor *)gridCellBackgroundColor;

#pragma mark - CGColor Accessors (for layer backgrounds)

+ (CGColorRef)backgroundCGColor;
+ (CGColorRef)secondaryBackgroundCGColor;
+ (CGColorRef)panelBackgroundCGColor;

@end

NS_ASSUME_NONNULL_END


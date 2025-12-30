/**
 * DateFormatters.h
 * Centralized date formatting utilities
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DateFormatters : NSObject

/**
 * Parse EXIF date string (format: "yyyy:MM:dd HH:mm:ss")
 * @param dateString EXIF date string
 * @return Parsed date or nil if invalid
 */
+ (nullable NSDate *)dateFromExifString:(nullable NSString *)dateString;

/**
 * Format date for display (medium date, short time)
 * @param date Date to format
 * @return Formatted string or nil if date is nil
 */
+ (nullable NSString *)displayStringFromDate:(nullable NSDate *)date;

/**
 * Format date for display (date only, medium style)
 * @param date Date to format
 * @return Formatted string or nil if date is nil
 */
+ (nullable NSString *)dateOnlyStringFromDate:(nullable NSDate *)date;

@end

NS_ASSUME_NONNULL_END


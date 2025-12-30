/**
 * DateFormatters.m
 * Centralized date formatting implementation
 */

#import "DateFormatters.h"

@implementation DateFormatters

#pragma mark - Shared Formatters

+ (NSDateFormatter *)exifDateFormatter {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy:MM:dd HH:mm:ss";
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return formatter;
}

+ (NSDateFormatter *)displayDateFormatter {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
    });
    return formatter;
}

+ (NSDateFormatter *)dateOnlyFormatter {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterNoStyle;
    });
    return formatter;
}

#pragma mark - Public Methods

+ (NSDate *)dateFromExifString:(NSString *)dateString {
    if (!dateString) {
        return nil;
    }
    return [[self exifDateFormatter] dateFromString:dateString];
}

+ (NSString *)displayStringFromDate:(NSDate *)date {
    if (!date) {
        return nil;
    }
    return [[self displayDateFormatter] stringFromDate:date];
}

+ (NSString *)dateOnlyStringFromDate:(NSDate *)date {
    if (!date) {
        return nil;
    }
    return [[self dateOnlyFormatter] stringFromDate:date];
}

@end


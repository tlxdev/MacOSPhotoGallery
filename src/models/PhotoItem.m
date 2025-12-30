/**
 * PhotoItem.m
 * Photo model implementation with metadata loading
 */

#import "PhotoItem.h"
#import <ImageIO/ImageIO.h>
#import "../utils/DateFormatters.h"

@interface PhotoItem ()

@property (nonatomic, copy, readwrite) NSString *path;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, assign, readwrite) uint64_t fileSize;
@property (nonatomic, strong, readwrite) NSDate *createdDate;
@property (nonatomic, strong, readwrite) NSDate *modifiedDate;

@property (nonatomic, assign, readwrite) CGSize dimensions;
@property (nonatomic, copy, readwrite, nullable) NSString *cameraMake;
@property (nonatomic, copy, readwrite, nullable) NSString *cameraModel;
@property (nonatomic, copy, readwrite, nullable) NSString *exposureTime;
@property (nonatomic, copy, readwrite, nullable) NSString *fNumber;
@property (nonatomic, copy, readwrite, nullable) NSNumber *iso;
@property (nonatomic, copy, readwrite, nullable) NSString *focalLength;
@property (nonatomic, copy, readwrite, nullable) NSDate *dateTaken;
@property (nonatomic, copy, readwrite, nullable) NSString *colorSpace;
@property (nonatomic, assign, readwrite) BOOL metadataLoaded;

@end

@implementation PhotoItem

- (instancetype)initWithPath:(NSString *)path
                        name:(NSString *)name
                    fileSize:(uint64_t)fileSize
                 createdDate:(NSDate *)createdDate
                modifiedDate:(NSDate *)modifiedDate {
    self = [super init];
    if (self) {
        _path = [path copy];
        _name = [name copy];
        _fileSize = fileSize;
        _createdDate = createdDate;
        _modifiedDate = modifiedDate;
        _dimensions = CGSizeZero;
        _metadataLoaded = NO;
    }
    return self;
}

- (void)loadMetadata {
    if (self.metadataLoaded) {
        return;
    }
    
    NSURL *url = [NSURL fileURLWithPath:self.path];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    
    if (source == NULL) {
        self.metadataLoaded = YES;
        return;
    }
    
    NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
    
    if (properties) {
        /* Dimensions */
        NSNumber *width = properties[(__bridge NSString *)kCGImagePropertyPixelWidth];
        NSNumber *height = properties[(__bridge NSString *)kCGImagePropertyPixelHeight];
        if (width && height) {
            self.dimensions = CGSizeMake(width.doubleValue, height.doubleValue);
        }
        
        /* Color space */
        self.colorSpace = properties[(__bridge NSString *)kCGImagePropertyColorModel];
        
        /* EXIF data */
        NSDictionary *exif = properties[(__bridge NSString *)kCGImagePropertyExifDictionary];
        if (exif) {
            self.exposureTime = [self formatExposureTime:exif[(__bridge NSString *)kCGImagePropertyExifExposureTime]];
            self.fNumber = [self formatFNumber:exif[(__bridge NSString *)kCGImagePropertyExifFNumber]];
            self.iso = [exif[(__bridge NSString *)kCGImagePropertyExifISOSpeedRatings] firstObject];
            self.focalLength = [self formatFocalLength:exif[(__bridge NSString *)kCGImagePropertyExifFocalLength]];
            self.dateTaken = [self parseExifDate:exif[(__bridge NSString *)kCGImagePropertyExifDateTimeOriginal]];
        }
        
        /* TIFF data (camera info) */
        NSDictionary *tiff = properties[(__bridge NSString *)kCGImagePropertyTIFFDictionary];
        if (tiff) {
            self.cameraMake = tiff[(__bridge NSString *)kCGImagePropertyTIFFMake];
            self.cameraModel = tiff[(__bridge NSString *)kCGImagePropertyTIFFModel];
        }
    }
    
    CFRelease(source);
    self.metadataLoaded = YES;
}

#pragma mark - Formatting Helpers

- (NSString *)formatExposureTime:(NSNumber *)exposure {
    if (!exposure) {
        return nil;
    }
    
    double value = exposure.doubleValue;
    if (value >= 1.0) {
        return [NSString stringWithFormat:@"%.1fs", value];
    } else if (value > 0) {
        return [NSString stringWithFormat:@"1/%.0fs", 1.0 / value];
    }
    return nil;
}

- (NSString *)formatFNumber:(NSNumber *)fNumber {
    if (!fNumber) {
        return nil;
    }
    return [NSString stringWithFormat:@"f/%.1f", fNumber.doubleValue];
}

- (NSString *)formatFocalLength:(NSNumber *)focal {
    if (!focal) {
        return nil;
    }
    return [NSString stringWithFormat:@"%.0fmm", focal.doubleValue];
}

- (NSDate *)parseExifDate:(NSString *)dateString {
    return [DateFormatters dateFromExifString:dateString];
}

+ (NSString *)formattedFileSize:(uint64_t)bytes {
    static const char *units[] = {"B", "KB", "MB", "GB", "TB"};
    int unitIndex = 0;
    double size = (double)bytes;
    
    while (size >= 1024.0 && unitIndex < 4) {
        size /= 1024.0;
        unitIndex++;
    }
    
    if (unitIndex == 0) {
        return [NSString stringWithFormat:@"%llu %s", bytes, units[unitIndex]];
    }
    return [NSString stringWithFormat:@"%.1f %s", size, units[unitIndex]];
}

@end


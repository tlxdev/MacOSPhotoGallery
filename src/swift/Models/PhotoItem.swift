/**
 * PhotoItem.swift
 * Model representing a single photo with metadata
 */

import Foundation
import AppKit
import ImageIO

struct PhotoItem: Identifiable, Hashable {
    let id: UUID
    let path: String
    let name: String
    let fileSize: UInt64
    let createdDate: Date
    let modifiedDate: Date
    let index: Int
    
    // Lazy-loaded metadata
    private(set) var dimensions: CGSize = .zero
    private(set) var cameraMake: String?
    private(set) var cameraModel: String?
    private(set) var exposureTime: String?
    private(set) var fNumber: String?
    private(set) var iso: Int?
    private(set) var focalLength: String?
    private(set) var dateTaken: Date?
    private(set) var colorSpace: String?
    private(set) var metadataLoaded: Bool = false
    
    init(path: String, name: String, fileSize: UInt64, createdDate: Date, modifiedDate: Date, index: Int) {
        self.id = UUID()
        self.path = path
        self.name = name
        self.fileSize = fileSize
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.index = index
    }
    
    mutating func loadMetadata() {
        guard !metadataLoaded else { return }
        
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            metadataLoaded = true
            return
        }
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            metadataLoaded = true
            return
        }
        
        // Dimensions
        if let width = properties[kCGImagePropertyPixelWidth as String] as? Double,
           let height = properties[kCGImagePropertyPixelHeight as String] as? Double {
            dimensions = CGSize(width: width, height: height)
        }
        
        // Color space
        colorSpace = properties[kCGImagePropertyColorModel as String] as? String
        
        // EXIF data
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let exposure = exif[kCGImagePropertyExifExposureTime as String] as? Double {
                exposureTime = Self.formatExposureTime(exposure)
            }
            if let fNum = exif[kCGImagePropertyExifFNumber as String] as? Double {
                fNumber = String(format: "f/%.1f", fNum)
            }
            if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int], 
               let firstISO = isoArray.first {
                iso = firstISO
            }
            if let focal = exif[kCGImagePropertyExifFocalLength as String] as? Double {
                focalLength = String(format: "%.0fmm", focal)
            }
            if let dateString = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                dateTaken = DateFormatters.parseExifDate(dateString)
            }
        }
        
        // TIFF data (camera info)
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            cameraMake = tiff[kCGImagePropertyTIFFMake as String] as? String
            cameraModel = tiff[kCGImagePropertyTIFFModel as String] as? String
        }
        
        metadataLoaded = true
    }
    
    private static func formatExposureTime(_ value: Double) -> String {
        if value >= 1.0 {
            return String(format: "%.1fs", value)
        } else if value > 0 {
            return String(format: "1/%.0fs", 1.0 / value)
        }
        return ""
    }
    
    static func formattedFileSize(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        if unitIndex == 0 {
            return "\(bytes) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", size, units[unitIndex])
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
    
    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.path == rhs.path
    }
}

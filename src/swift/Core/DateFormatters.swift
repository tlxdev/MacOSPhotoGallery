/**
 * DateFormatters.swift
 * Cached DateFormatter instances for performance
 */

import Foundation

/// Cached DateFormatters to avoid repeated instantiation
enum DateFormatters {
    /// Formatter for displaying dates in UI (medium date, short time)
    static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Formatter for parsing EXIF date strings
    static let exifFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    /// Format a date for display in the UI
    static func formatForDisplay(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }
    
    /// Parse an EXIF date string
    static func parseExifDate(_ dateString: String) -> Date? {
        exifFormatter.date(from: dateString)
    }
}


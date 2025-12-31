/**
 * Logger.swift
 * Centralized logging infrastructure using os.log
 */

import Foundation
import os

/// Application-wide logging categories
enum LogCategory: String {
    case general = "General"
    case photoStore = "PhotoStore"
    case imageCache = "ImageCache"
    case thumbnailCache = "ThumbnailCache"
    case fileOperations = "FileOperations"
    case ui = "UI"
}

/// Centralized logger for the PhotoViewer app
struct AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.photoviewer.app"
    
    private static let loggers: [LogCategory: Logger] = {
        Dictionary(uniqueKeysWithValues: LogCategory.allCases.map { category in
            (category, Logger(subsystem: subsystem, category: category.rawValue))
        })
    }()
    
    static func debug(_ message: String, category: LogCategory = .general) {
        loggers[category]?.debug("\(message, privacy: .public)")
    }
    
    static func info(_ message: String, category: LogCategory = .general) {
        loggers[category]?.info("\(message, privacy: .public)")
    }
    
    static func warning(_ message: String, category: LogCategory = .general) {
        loggers[category]?.warning("\(message, privacy: .public)")
    }
    
    static func error(_ message: String, category: LogCategory = .general) {
        loggers[category]?.error("\(message, privacy: .public)")
    }
    
    static func fault(_ message: String, category: LogCategory = .general) {
        loggers[category]?.fault("\(message, privacy: .public)")
    }
    
    /// Log with custom privacy for sensitive paths
    static func logPath(_ message: String, path: String, category: LogCategory = .fileOperations) {
        loggers[category]?.info("\(message, privacy: .public): \(path, privacy: .private)")
    }
}

extension LogCategory: CaseIterable {}


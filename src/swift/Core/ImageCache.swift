/**
 * ImageCache.swift
 * Unified image and thumbnail cache using LRU eviction
 * Includes memory pressure handling for automatic cache eviction
 */

import Foundation
import AppKit
import ImageIO
import Dispatch
import SwiftUI

// MARK: - Sendable Conformance

extension NSImage: @retroactive @unchecked Sendable {}

// MARK: - Image Load Result

struct ImageLoadResult: @unchecked Sendable {
    let image: NSImage?
    let error: String?
    
    static func success(_ image: NSImage) -> ImageLoadResult {
        ImageLoadResult(image: image, error: nil)
    }
    
    static func failure(_ error: String) -> ImageLoadResult {
        ImageLoadResult(image: nil, error: error)
    }
}

// MARK: - Image Cache Protocol (for dependency injection)

protocol ImageCaching: Actor {
    func fullSizeImage(for path: String) async -> NSImage?
    func setFullSizeImage(_ image: NSImage, for path: String) async
    func thumbnail(for path: String) async -> NSImage?
    func setThumbnail(_ image: NSImage, for path: String) async
    func generateThumbnail(for path: String, size: CGFloat) async -> NSImage?
    func loadFullSizeImage(at path: String) async -> ImageLoadResult
    func clearFullSizeCache() async
    func clearThumbnailCache() async
    func clearAll() async
    func handleMemoryPressure(level: MemoryPressureLevel) async
}

// MARK: - Memory Pressure Level

enum MemoryPressureLevel: Sendable {
    case normal
    case warning
    case critical
}

// MARK: - Memory Pressure Monitor

final class MemoryPressureMonitor: @unchecked Sendable {
    private let memoryPressureSource: DispatchSourceMemoryPressure
    private let onPressureChange: @Sendable (MemoryPressureLevel) -> Void
    
    init(onPressureChange: @escaping @Sendable (MemoryPressureLevel) -> Void) {
        self.onPressureChange = onPressureChange
        self.memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        
        memoryPressureSource.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = self.memoryPressureSource.data
            
            let level: MemoryPressureLevel
            if event.contains(.critical) {
                level = .critical
            } else if event.contains(.warning) {
                level = .warning
            } else {
                level = .normal
            }
            
            self.onPressureChange(level)
        }
        
        memoryPressureSource.resume()
        AppLogger.info("Memory pressure monitor started", category: .imageCache)
    }
    
    deinit {
        memoryPressureSource.cancel()
    }
}


// MARK: - Unified Image Cache

/// Unified cache for both full-size images and thumbnails
/// Uses O(1) LRU eviction for optimal performance
/// Responds to system memory pressure by clearing caches
actor ImageCacheManager: ImageCaching {
    static let shared: ImageCacheManager = {
        let cache = ImageCacheManager()
        // Set up memory monitoring after creation using a task
        Task { await cache.startMemoryMonitoring() }
        return cache
    }()
    
    /// Cache configuration
    enum CacheConfig {
        static let maxFullSizeImages = 20
        static let maxThumbnails = 500
    }
    
    private let fullSizeCache: LRUCache<String, NSImage>
    private let thumbnailCache: LRUCache<String, NSImage>
    private var memoryMonitor: MemoryPressureMonitor?
    
    init(
        fullSizeCacheSize: Int = CacheConfig.maxFullSizeImages,
        thumbnailCacheSize: Int = CacheConfig.maxThumbnails
    ) {
        self.fullSizeCache = LRUCache(maxSize: fullSizeCacheSize)
        self.thumbnailCache = LRUCache(maxSize: thumbnailCacheSize)
        self.memoryMonitor = nil
    }
    
    /// Starts memory pressure monitoring - called after initialization
    func startMemoryMonitoring() {
        guard memoryMonitor == nil else { return }
        let cache = self
        self.memoryMonitor = MemoryPressureMonitor { level in
            Task {
                await cache.handleMemoryPressure(level: level)
            }
        }
    }
    
    // MARK: - Memory Pressure Handling
    
    func handleMemoryPressure(level: MemoryPressureLevel) async {
        switch level {
        case .normal:
            break
        case .warning:
            // On warning, clear full-size images (largest memory consumers)
            await fullSizeCache.clear()
            AppLogger.warning("Memory pressure warning - cleared full-size image cache", category: .imageCache)
        case .critical:
            // On critical, clear everything
            await fullSizeCache.clear()
            await thumbnailCache.clear()
            AppLogger.error("Memory pressure critical - cleared all caches", category: .imageCache)
        }
    }
    
    // MARK: - Full Size Image Operations
    
    func fullSizeImage(for path: String) async -> NSImage? {
        await fullSizeCache.get(path)
    }
    
    func setFullSizeImage(_ image: NSImage, for path: String) async {
        await fullSizeCache.set(path, value: image)
        AppLogger.debug("Cached full-size image: \(path)", category: .imageCache)
    }
    
    // MARK: - Thumbnail Operations
    
    func thumbnail(for path: String) async -> NSImage? {
        await thumbnailCache.get(path)
    }
    
    func setThumbnail(_ image: NSImage, for path: String) async {
        await thumbnailCache.set(path, value: image)
    }
    
    /// Generate and cache a thumbnail
    func generateThumbnail(for path: String, size: CGFloat = 320) async -> NSImage? {
        // Check cache first
        if let cached = await thumbnailCache.get(path) {
            return cached
        }
        
        // Generate on background
        let thumbnail = await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            Task.detached(priority: .utility) {
                let result = Self.createThumbnail(for: path, size: size)
                continuation.resume(returning: result)
            }
        }
        
        if let thumbnail = thumbnail {
            await thumbnailCache.set(path, value: thumbnail)
        }
        
        return thumbnail
    }
    
    // MARK: - Image Loading
    
    /// Load a full-size image from disk (async, with caching)
    func loadFullSizeImage(at path: String) async -> ImageLoadResult {
        // Check cache
        if let cached = await fullSizeCache.get(path) {
            return .success(cached)
        }
        
        // Load from disk
        let result = await loadImageFromDisk(at: path)
        
        if let image = result.image {
            await fullSizeCache.set(path, value: image)
        }
        
        return result
    }
    
    // MARK: - Clear Operations
    
    func clearFullSizeCache() async {
        await fullSizeCache.clear()
        AppLogger.info("Cleared full-size image cache", category: .imageCache)
    }
    
    func clearThumbnailCache() async {
        await thumbnailCache.clear()
        AppLogger.info("Cleared thumbnail cache", category: .thumbnailCache)
    }
    
    func clearAll() async {
        await fullSizeCache.clear()
        await thumbnailCache.clear()
        AppLogger.info("Cleared all image caches", category: .imageCache)
    }
    
    // MARK: - Private Helpers
    
    private static nonisolated func createThumbnail(for path: String, size: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            AppLogger.warning("Failed to create image source for thumbnail: \(path)", category: .thumbnailCache)
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: size,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            AppLogger.warning("Failed to generate thumbnail: \(path)", category: .thumbnailCache)
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: .zero)
    }
}

// MARK: - Disk Image Loading

@Sendable
func loadImageFromDisk(at path: String) async -> ImageLoadResult {
    await Task.detached(priority: .userInitiated) {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: path) else {
            AppLogger.warning("File not found: \(path)", category: .fileOperations)
            return ImageLoadResult.failure("File not found")
        }
        
        guard fileManager.isReadableFile(atPath: path) else {
            AppLogger.warning("Cannot read file: \(path)", category: .fileOperations)
            return ImageLoadResult.failure("Cannot read file")
        }
        
        let url = URL(fileURLWithPath: path)
        guard let loadedImage = NSImage(contentsOf: url) else {
            AppLogger.warning("Unable to load image: \(path)", category: .fileOperations)
            return ImageLoadResult.failure("Unable to load image")
        }
        
        return ImageLoadResult.success(loadedImage)
    }.value
}

// MARK: - Environment Key for Dependency Injection

struct ImageCacheKey: EnvironmentKey {
    static let defaultValue: ImageCacheManager = .shared
}

extension EnvironmentValues {
    var imageCache: ImageCacheManager {
        get { self[ImageCacheKey.self] }
        set { self[ImageCacheKey.self] = newValue }
    }
}


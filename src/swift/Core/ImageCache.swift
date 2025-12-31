/**
 * ImageCache.swift
 * Ultra high-performance image caching system
 * 
 * Optimizations:
 * - Display-sized image loading (downsampled to screen resolution)
 * - Parallel preloading with priority queue
 * - Large LRU caches with memory pressure handling
 * - Batch thumbnail prefetching
 * - CGImageSource subsampling for instant loading
 */

import Foundation
import AppKit
import ImageIO
import Dispatch
import SwiftUI
import QuickLookThumbnailing

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

// MARK: - Preload Priority

enum PreloadPriority: Int, Comparable, Sendable {
    case critical = 0   // Current image
    case high = 1       // Adjacent images (+/- 1)
    case medium = 2     // Nearby images (+/- 2-5)
    case low = 3        // Background prefetch (+/- 6-15)
    
    static func < (lhs: PreloadPriority, rhs: PreloadPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Preload Request

struct PreloadRequest: Sendable {
    let path: String
    let priority: PreloadPriority
    let maxDimension: CGFloat
}

// MARK: - Image Cache Protocol (for dependency injection)

protocol ImageCaching: Actor {
    func fullSizeImage(for path: String) async -> NSImage?
    func setFullSizeImage(_ image: NSImage, for path: String) async
    func thumbnail(for path: String) async -> NSImage?
    func setThumbnail(_ image: NSImage, for path: String) async
    func generateThumbnail(for path: String, size: CGFloat) async -> NSImage?
    func loadFullSizeImage(at path: String) async -> ImageLoadResult
    func loadDisplayImage(at path: String, maxDimension: CGFloat) async -> ImageLoadResult
    func clearFullSizeCache() async
    func clearThumbnailCache() async
    func clearAll() async
    func handleMemoryPressure(level: MemoryPressureLevel) async
    func preloadImages(requests: [PreloadRequest]) async
    func prefetchThumbnails(paths: [String], size: CGFloat) async
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

/// Ultra high-performance image cache
/// - Large caches (50 full-size, 2000 thumbnails)
/// - Display-sized loading with subsampling
/// - Parallel preloading with priority
/// - Memory pressure handling
actor ImageCacheManager: ImageCaching {
    static let shared: ImageCacheManager = {
        let cache = ImageCacheManager()
        Task { await cache.startMemoryMonitoring() }
        return cache
    }()
    
    /// Cache configuration - LARGE for instant loading
    enum CacheConfig {
        static let maxFullSizeImages = 50      // 50 display-sized images
        static let maxThumbnails = 2000        // 2000 thumbnails for smooth grid scrolling
        static let defaultDisplayMaxDimension: CGFloat = 3840  // 4K max
        static let parallelLoadCount = 4       // Parallel preload operations
    }
    
    private let fullSizeCache: LRUCache<String, NSImage>
    private let thumbnailCache: LRUCache<String, NSImage>
    private var memoryMonitor: MemoryPressureMonitor?
    
    // Preloading state
    private var preloadTasks: [String: Task<Void, Never>] = [:]
    private let preloadQueue = DispatchQueue(label: "com.photoviewer.preload", qos: .userInitiated, attributes: .concurrent)
    
    init(
        fullSizeCacheSize: Int = CacheConfig.maxFullSizeImages,
        thumbnailCacheSize: Int = CacheConfig.maxThumbnails
    ) {
        self.fullSizeCache = LRUCache(maxSize: fullSizeCacheSize)
        self.thumbnailCache = LRUCache(maxSize: thumbnailCacheSize)
        self.memoryMonitor = nil
    }
    
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
            // On warning, clear half of full-size cache
            let count = await fullSizeCache.count
            for _ in 0..<(count / 2) {
                await fullSizeCache.evictOldest()
            }
            AppLogger.warning("Memory pressure warning - reduced full-size cache", category: .imageCache)
        case .critical:
            await fullSizeCache.clear()
            // Keep thumbnails as they're small
            AppLogger.error("Memory pressure critical - cleared full-size cache", category: .imageCache)
        }
    }
    
    // MARK: - Full Size Image Operations
    
    func fullSizeImage(for path: String) async -> NSImage? {
        await fullSizeCache.get(path)
    }
    
    func setFullSizeImage(_ image: NSImage, for path: String) async {
        await fullSizeCache.set(path, value: image)
    }
    
    // MARK: - Thumbnail Operations
    
    func thumbnail(for path: String) async -> NSImage? {
        await thumbnailCache.get(path)
    }
    
    func setThumbnail(_ image: NSImage, for path: String) async {
        await thumbnailCache.set(path, value: image)
    }
    
    /// Generate thumbnail using CGImageSource subsampling - extremely fast
    func generateThumbnail(for path: String, size: CGFloat = 320) async -> NSImage? {
        // Check cache first
        if let cached = await thumbnailCache.get(path) {
            return cached
        }
        
        // Generate using optimized method
        let thumbnail = await Task.detached(priority: .userInitiated) {
            Self.createOptimizedThumbnail(for: path, size: size)
        }.value
        
        if let thumbnail = thumbnail {
            await thumbnailCache.set(path, value: thumbnail)
        }
        
        return thumbnail
    }
    
    // MARK: - Display Image Loading (Optimized)
    
    /// Load image downsampled to display size - this is the key optimization
    func loadDisplayImage(at path: String, maxDimension: CGFloat = CacheConfig.defaultDisplayMaxDimension) async -> ImageLoadResult {
        // Check cache
        if let cached = await fullSizeCache.get(path) {
            return .success(cached)
        }
        
        // Load with subsampling
        let result = await Task.detached(priority: .userInitiated) {
            Self.loadSubsampledImage(at: path, maxDimension: maxDimension)
        }.value
        
        if let image = result.image {
            await fullSizeCache.set(path, value: image)
        }
        
        return result
    }
    
    /// Legacy full-size loading (for compatibility)
    func loadFullSizeImage(at path: String) async -> ImageLoadResult {
        await loadDisplayImage(at: path, maxDimension: CacheConfig.defaultDisplayMaxDimension)
    }
    
    // MARK: - Parallel Preloading
    
    /// Preload images in parallel with priority
    func preloadImages(requests: [PreloadRequest]) async {
        // Sort by priority
        let sortedRequests = requests.sorted { $0.priority < $1.priority }
        
        // Cancel any existing preloads for paths not in new requests
        let newPaths = Set(requests.map(\.path))
        for (path, task) in preloadTasks {
            if !newPaths.contains(path) {
                task.cancel()
                preloadTasks.removeValue(forKey: path)
            }
        }
        
        // Process in parallel batches
        await withTaskGroup(of: Void.self) { group in
            var activeCount = 0
            
            for request in sortedRequests {
                // Skip if already cached or loading
                if await fullSizeCache.contains(request.path) {
                    continue
                }
                if preloadTasks[request.path] != nil {
                    continue
                }
                
                // Limit parallel loads
                if activeCount >= CacheConfig.parallelLoadCount {
                    // Wait for one to complete
                    await group.next()
                    activeCount -= 1
                }
                
                activeCount += 1
                let path = request.path
                let maxDim = request.maxDimension
                let cache = self
                
                group.addTask {
                    let result = await Task.detached(priority: request.priority == .critical ? .high : .medium) {
                        Self.loadSubsampledImage(at: path, maxDimension: maxDim)
                    }.value
                    
                    if let image = result.image {
                        await cache.setFullSizeImage(image, for: path)
                    }
                }
            }
        }
    }
    
    /// Prefetch thumbnails in batch - for grid view
    func prefetchThumbnails(paths: [String], size: CGFloat) async {
        await withTaskGroup(of: Void.self) { group in
            for path in paths {
                // Skip if cached
                if await thumbnailCache.contains(path) {
                    continue
                }
                
                let cache = self
                group.addTask {
                    let thumb = await Task.detached(priority: .medium) {
                        Self.createOptimizedThumbnail(for: path, size: size)
                    }.value
                    
                    if let thumb = thumb {
                        await cache.setThumbnail(thumb, for: path)
                    }
                }
            }
        }
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
    
    // MARK: - Private Optimized Image Loading
    
    /// Load image with subsampling - loads at reduced resolution from disk
    /// This is MUCH faster than loading full res and scaling
    private static nonisolated func loadSubsampledImage(at path: String, maxDimension: CGFloat) -> ImageLoadResult {
        let url = URL(fileURLWithPath: path)
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return .failure("Cannot read image file")
        }
        
        // Get original dimensions
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            // Fallback to regular loading
            if let image = NSImage(contentsOf: url) {
                return .success(image)
            }
            return .failure("Cannot read image properties")
        }
        
        // Calculate subsample factor
        let maxOriginal = max(width, height)
        
        // If image is smaller than max dimension, load at full size
        if maxOriginal <= maxDimension {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceShouldAllowFloat: true
            ]
            
            if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) {
                return .success(NSImage(cgImage: cgImage, size: NSSize(width: width, height: height)))
            }
        }
        
        // Use thumbnail generation with max size - this uses hardware decoding
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            let size = NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
            return .success(NSImage(cgImage: cgImage, size: size))
        }
        
        // Ultimate fallback
        if let image = NSImage(contentsOf: url) {
            return .success(image)
        }
        
        return .failure("Failed to decode image")
    }
    
    /// Create thumbnail using CGImageSource - optimized for speed
    private static nonisolated func createOptimizedThumbnail(for path: String, size: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: size,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: .zero)
    }
}

// MARK: - Legacy Disk Image Loading (for compatibility)

@Sendable
func loadImageFromDisk(at path: String) async -> ImageLoadResult {
    await Task.detached(priority: .userInitiated) {
        let url = URL(fileURLWithPath: path)
        
        // Use optimized subsampled loading
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return ImageLoadResult.failure("Cannot read file")
        }
        
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: ImageCacheManager.CacheConfig.defaultDisplayMaxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            let size = NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
            return ImageLoadResult.success(NSImage(cgImage: cgImage, size: size))
        }
        
        // Fallback
        if let image = NSImage(contentsOf: url) {
            return ImageLoadResult.success(image)
        }
        
        return ImageLoadResult.failure("Unable to load image")
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

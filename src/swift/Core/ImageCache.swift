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
/// - Large caches (50 full-size, 5000 thumbnails)
/// - Eager thumbnail pre-generation on folder scan
/// - EXIF embedded thumbnail extraction for instant preview
/// - High parallelism with concurrency control
/// - Priority queue for visible cells
actor ImageCacheManager: ImageCaching {
    static let shared: ImageCacheManager = {
        let cache = ImageCacheManager()
        Task { await cache.startMemoryMonitoring() }
        return cache
    }()
    
    /// Cache configuration - LARGE for instant loading
    enum CacheConfig {
        static let maxFullSizeImages = 50           // 50 display-sized images
        static let maxThumbnails = 5000             // 5000 thumbnails for smooth grid scrolling
        static let defaultDisplayMaxDimension: CGFloat = 3840  // 4K max
        static let parallelLoadCount = 4            // Parallel full-size preload operations
        static let thumbnailParallelCount = 16      // High parallelism for thumbnails
        static let eagerPreloadBatchSize = 200      // How many thumbnails to pre-generate immediately
    }
    
    private let fullSizeCache: LRUCache<String, NSImage>
    private let thumbnailCache: LRUCache<String, NSImage>
    private var memoryMonitor: MemoryPressureMonitor?
    
    // Preloading state
    private var preloadTasks: [String: Task<Void, Never>] = [:]
    private let preloadQueue = DispatchQueue(label: "com.photoviewer.preload", qos: .userInitiated, attributes: .concurrent)
    
    // Eager thumbnail generation state
    private var eagerGenerationTask: Task<Void, Never>?
    private var priorityPaths: Set<String> = []  // Paths that should be loaded with high priority
    
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
    
    /// Prefetch thumbnails in batch - for grid view (with concurrency limit)
    func prefetchThumbnails(paths: [String], size: CGFloat) async {
        // Use a limited number of concurrent operations
        // First filter out already cached paths
        var uncachedPaths: [String] = []
        for path in paths {
            if !(await self.thumbnailCache.contains(path)) {
                uncachedPaths.append(path)
            }
        }
        
        guard !uncachedPaths.isEmpty else { return }
        
        // Mark these as priority paths
        for path in uncachedPaths {
            self.priorityPaths.insert(path)
        }
        
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            
            for path in uncachedPaths {
                // Limit concurrency
                if inFlight >= CacheConfig.thumbnailParallelCount {
                    await group.next()
                    inFlight -= 1
                }
                
                inFlight += 1
                let cache = self
                
                group.addTask {
                    let thumb = await Task.detached(priority: .high) {
                        Self.createOptimizedThumbnail(for: path, size: size)
                    }.value
                    
                    if let thumb = thumb {
                        await cache.setThumbnail(thumb, for: path)
                    }
                }
            }
        }
        
        // Clear priority paths
        for path in uncachedPaths {
            self.priorityPaths.remove(path)
        }
    }
    
    // MARK: - Eager Thumbnail Pre-Generation
    
    /// Start eager thumbnail generation for all photos in background
    /// Call this immediately after folder scan completes
    func startEagerThumbnailGeneration(paths: [String], size: CGFloat) {
        // Cancel any existing eager generation
        eagerGenerationTask?.cancel()
        
        eagerGenerationTask = Task { [weak self] in
            guard let self = self else { return }
            await self.generateThumbnailsEagerly(paths: paths, size: size)
        }
    }
    
    /// Generate thumbnails eagerly in batches
    private func generateThumbnailsEagerly(paths: [String], size: CGFloat) async {
        let batchSize = CacheConfig.eagerPreloadBatchSize
        let totalPaths = paths
        
        // Process in batches to avoid overwhelming the system
        var processed = 0
        
        while processed < totalPaths.count {
            // Check for cancellation
            if Task.isCancelled { return }
            
            let end = min(processed + batchSize, totalPaths.count)
            let batch = Array(totalPaths[processed..<end])
            
            // Filter out already cached
            var uncached: [String] = []
            for path in batch {
                if !(await self.thumbnailCache.contains(path)) {
                    uncached.append(path)
                }
            }
            
            // Skip priority paths - they're being loaded by the UI
            let nonPriorityPaths = uncached.filter { !self.priorityPaths.contains($0) }
            
            if !nonPriorityPaths.isEmpty {
                // Generate this batch with controlled parallelism
                await withTaskGroup(of: Void.self) { group in
                    var inFlight = 0
                    
                    for path in nonPriorityPaths {
                        if Task.isCancelled { return }
                        
                        // Limit concurrency
                        if inFlight >= CacheConfig.thumbnailParallelCount {
                            await group.next()
                            inFlight -= 1
                        }
                        
                        inFlight += 1
                        let cache = self
                        
                        group.addTask {
                            // Use low priority for background generation
                            let thumb = await Task.detached(priority: .utility) {
                                Self.createOptimizedThumbnail(for: path, size: size)
                            }.value
                            
                            if let thumb = thumb {
                                await cache.setThumbnail(thumb, for: path)
                            }
                        }
                    }
                }
            }
            
            processed = end
            
            // Small yield to let UI-triggered loads take priority
            if processed < totalPaths.count {
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
        }
    }
    
    /// Cancel eager generation (e.g., when switching folders)
    func cancelEagerGeneration() {
        eagerGenerationTask?.cancel()
        eagerGenerationTask = nil
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
        
        // First try: Use embedded thumbnail if available (instant for JPEGs)
        // This only works if the image has an embedded EXIF thumbnail
        let embeddedOptions: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: size,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,  // Don't generate, only use embedded
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, embeddedOptions as CFDictionary) {
            // Check if the embedded thumbnail is big enough
            if CGFloat(cgImage.width) >= size * 0.5 || CGFloat(cgImage.height) >= size * 0.5 {
                return NSImage(cgImage: cgImage, size: .zero)
            }
        }
        
        // Second: Generate thumbnail with subsampling (hardware accelerated)
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: size,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceSubsampleFactor: 4  // Subsample by 4x for speed
        ]
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: .zero)
    }
    
    /// Extract embedded EXIF thumbnail - extremely fast (no decoding needed)
    private static nonisolated func extractEmbeddedThumbnail(for path: String) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        
        // Get properties including the embedded thumbnail
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exifDict = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let thumbnailData = exifDict[kCGImagePropertyExifUserComment] as? Data,
              let thumbnail = NSImage(data: thumbnailData) else {
            // Try the TIFF thumbnail
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: 320,
                kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
                kCGImageSourceShouldCacheImmediately: true
            ]
            
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return NSImage(cgImage: cgImage, size: .zero)
            }
            return nil
        }
        
        return thumbnail
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

// MARK: - Async Array Extensions

extension Array {
    /// Async filter that processes elements concurrently
    func asyncFilter(_ isIncluded: @escaping (Element) async -> Bool) async -> [Element] {
        await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, element) in self.enumerated() {
                group.addTask {
                    let included = await isIncluded(element)
                    return (index, included)
                }
            }
            
            var results = [Int: Bool]()
            for await (index, included) in group {
                results[index] = included
            }
            
            return self.enumerated().compactMap { index, element in
                results[index] == true ? element : nil
            }
        }
    }
}

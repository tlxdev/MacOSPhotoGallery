/**
 * ThumbnailCache.swift
 * Actor-based thumbnail cache for thread-safe caching
 */

import Foundation
import AppKit
import ImageIO

actor ThumbnailCache {
    static let shared = ThumbnailCache()
    
    private var cache: [String: NSImage] = [:]
    private let maxCacheSize = 500
    private var accessOrder: [String] = []
    
    private init() {}
    
    func thumbnail(for path: String) -> NSImage? {
        if let cached = cache[path] {
            // Move to end of access order (LRU)
            if let index = accessOrder.firstIndex(of: path) {
                accessOrder.remove(at: index)
                accessOrder.append(path)
            }
            return cached
        }
        return nil
    }
    
    func setThumbnail(_ image: NSImage, for path: String) {
        // Evict oldest if at capacity
        while cache.count >= maxCacheSize, let oldest = accessOrder.first {
            cache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }
        
        cache[path] = image
        accessOrder.append(path)
    }
    
    func generateThumbnail(for path: String, size: CGFloat = 320) async -> NSImage? {
        // Check cache first
        if let cached = thumbnail(for: path) {
            return cached
        }
        
        // Generate thumbnail
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
        
        let thumbnail = NSImage(cgImage: cgImage, size: .zero)
        setThumbnail(thumbnail, for: path)
        
        return thumbnail
    }
    
    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }
    
    func removeThumbnail(for path: String) {
        cache.removeValue(forKey: path)
        if let index = accessOrder.firstIndex(of: path) {
            accessOrder.remove(at: index)
        }
    }
}



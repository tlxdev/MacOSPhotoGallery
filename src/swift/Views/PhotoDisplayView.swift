/**
 * PhotoDisplayView.swift
 * Main photo display with zoom and pan - fills container
 * Includes image preloading and debounced loading indicator
 */

import SwiftUI
import AppKit

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

struct PhotoDisplayView: View {
    @EnvironmentObject var photoStore: PhotoStore
    @State private var image: NSImage?
    @State private var showLoading = false
    @State private var errorMessage: String?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var loadingTask: Task<Void, Never>?
    @State private var loadingDebounceTask: Task<Void, Never>?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if showLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if let img = image {
                    imageView(img, in: geometry)
                } else {
                    emptyView
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .onChange(of: photoStore.selectedIndex) { _, newIndex in
            loadCurrentPhoto()
            preloadAdjacentImages(around: newIndex)
        }
        .onChange(of: photoStore.photos) { _, _ in
            loadCurrentPhoto()
        }
        .onAppear {
            loadCurrentPhoto()
            if photoStore.selectedIndex >= 0 {
                preloadAdjacentImages(around: photoStore.selectedIndex)
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white.opacity(0.6))
            
            Text("Loading...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.orange.opacity(0.6))
            
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    private var emptyView: some View {
        Text("No photo selected")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.3))
    }
    
    private func imageView(_ image: NSImage, in geometry: GeometryProxy) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale = min(max(scale * delta, 0.5), 10)
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if scale > 1 {
                        scale = 1
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 2
                    }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: scale)
    }
    
    private func loadCurrentPhoto() {
        // Cancel any existing loading tasks
        loadingTask?.cancel()
        loadingDebounceTask?.cancel()
        showLoading = false
        
        guard let photo = photoStore.currentPhoto else {
            image = nil
            errorMessage = nil
            return
        }
        
        let path = photo.path
        
        // Check cache first
        Task {
            if let cached = await ImageCache.shared.image(for: path) {
                image = cached
                errorMessage = nil
                scale = 1.0
                offset = .zero
                lastOffset = .zero
                return
            }
            
            startLoading(path: path)
        }
    }
    
    private func startLoading(path: String) {
        errorMessage = nil
        
        // Reset zoom when changing photos
        scale = 1.0
        offset = .zero
        lastOffset = .zero
        
        // Debounce loading indicator - only show after 150ms
        loadingDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            if !Task.isCancelled {
                showLoading = true
            }
        }
        
        // Load image on background thread
        loadingTask = Task {
            let result = await loadImageFromDisk(at: path)
            
            guard !Task.isCancelled else { return }
            
            // Cancel the debounce task since we're done loading
            loadingDebounceTask?.cancel()
            showLoading = false
            
            if let loadedImage = result.image {
                await ImageCache.shared.setImage(loadedImage, for: path)
                image = loadedImage
                errorMessage = nil
            } else {
                image = nil
                errorMessage = result.error ?? "Unknown error"
            }
        }
    }
    
    private func preloadAdjacentImages(around index: Int) {
        // Capture the photos array
        let photos = photoStore.photos
        let count = photos.count
        let preloadRange = 5
        
        Task.detached(priority: .utility) {
            // Preload next images
            for offset in 1...preloadRange {
                let nextIndex = index + offset
                if nextIndex < count {
                    let path = photos[nextIndex].path
                    let cached = await ImageCache.shared.image(for: path)
                    if cached == nil {
                        let result = await loadImageFromDisk(at: path)
                        if let img = result.image {
                            await ImageCache.shared.setImage(img, for: path)
                        }
                    }
                }
            }
            
            // Preload previous images
            for offset in 1...preloadRange {
                let prevIndex = index - offset
                if prevIndex >= 0 {
                    let path = photos[prevIndex].path
                    let cached = await ImageCache.shared.image(for: path)
                    if cached == nil {
                        let result = await loadImageFromDisk(at: path)
                        if let img = result.image {
                            await ImageCache.shared.setImage(img, for: path)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Image Loading

@Sendable
private func loadImageFromDisk(at path: String) async -> ImageLoadResult {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            
            guard fileManager.fileExists(atPath: path) else {
                continuation.resume(returning: .failure("File not found"))
                return
            }
            
            guard fileManager.isReadableFile(atPath: path) else {
                continuation.resume(returning: .failure("Cannot read file"))
                return
            }
            
            let url = URL(fileURLWithPath: path)
            guard let loadedImage = NSImage(contentsOf: url) else {
                continuation.resume(returning: .failure("Unable to load image"))
                return
            }
            
            continuation.resume(returning: .success(loadedImage))
        }
    }
}

// MARK: - Image Cache

actor ImageCache {
    static let shared = ImageCache()
    
    private var cache: [String: NSImage] = [:]
    private var accessOrder: [String] = []
    private let maxSize = 20 // Keep 20 images in cache
    
    func image(for path: String) -> NSImage? {
        if let img = cache[path] {
            // Move to end of access order (LRU)
            if let index = accessOrder.firstIndex(of: path) {
                accessOrder.remove(at: index)
                accessOrder.append(path)
            }
            return img
        }
        return nil
    }
    
    func setImage(_ image: NSImage, for path: String) {
        // Already cached
        if cache[path] != nil {
            return
        }
        
        // Evict oldest if at capacity
        while cache.count >= maxSize, let oldest = accessOrder.first {
            cache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }
        
        cache[path] = image
        accessOrder.append(path)
    }
    
    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }
}

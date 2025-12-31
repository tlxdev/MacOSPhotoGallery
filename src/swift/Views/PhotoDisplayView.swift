/**
 * PhotoDisplayView.swift
 * Ultra-optimized photo display with instant loading
 * 
 * Optimizations:
 * - Display-sized image loading (downsampled)
 * - Aggressive parallel preloading (15 images ahead/behind)
 * - Priority-based loading (current > adjacent > far)
 * - Instant cache hits with no loading indicator for cached images
 */

import SwiftUI
import AppKit

struct PhotoDisplayView: View {
    @Environment(PhotoStore.self) private var photoStore
    @Environment(\.imageCache) private var imageCache
    @State private var image: NSImage?
    @State private var showLoading = false
    @State private var errorMessage: String?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var loadingTask: Task<Void, Never>?
    @State private var loadingDebounceTask: Task<Void, Never>?
    @State private var preloadTask: Task<Void, Never>?
    @State private var displayMaxDimension: CGFloat = 3840
    
    // Preload configuration - aggressive for instant loading
    private let preloadAhead = 15      // Preload 15 images ahead
    private let preloadBehind = 10     // Preload 10 images behind
    
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
            .onAppear {
                // Calculate appropriate max dimension based on screen
                updateDisplayMaxDimension(for: geometry)
            }
            .onChange(of: geometry.size) { _, newSize in
                updateDisplayMaxDimension(for: geometry)
            }
        }
        .onChange(of: photoStore.selectedIndex) { oldIndex, newIndex in
            loadCurrentPhoto()
            schedulePreloading(around: newIndex, previousIndex: oldIndex)
        }
        .onChange(of: photoStore.photos) { _, _ in
            loadCurrentPhoto()
        }
        .onAppear {
            loadCurrentPhoto()
            if photoStore.selectedIndex >= 0 {
                schedulePreloading(around: photoStore.selectedIndex, previousIndex: nil)
            }
        }
    }
    
    private func updateDisplayMaxDimension(for geometry: GeometryProxy) {
        // Use 2x for retina, capped at 4K
        let screenScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let maxDim = max(geometry.size.width, geometry.size.height) * screenScale
        displayMaxDimension = min(max(maxDim, 2560), 3840)
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
        let cache = imageCache
        let maxDim = displayMaxDimension
        
        // Check cache first - if hit, display instantly with NO loading indicator
        Task { @MainActor in
            if let cached = await cache.fullSizeImage(for: path) {
                image = cached
                errorMessage = nil
                resetZoom()
                return
            }
            
            // Not cached, need to load
            startLoading(path: path, maxDimension: maxDim)
        }
    }
    
    private func resetZoom() {
        scale = 1.0
        offset = .zero
        lastOffset = .zero
    }
    
    private func startLoading(path: String, maxDimension: CGFloat) {
        errorMessage = nil
        resetZoom()
        
        let cache = imageCache
        
        // Debounce loading indicator - only show after 100ms (reduced from 150ms)
        loadingDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if !Task.isCancelled {
                showLoading = true
            }
        }
        
        // Load image using optimized display-sized loading
        loadingTask = Task { @MainActor in
            let result = await cache.loadDisplayImage(at: path, maxDimension: maxDimension)
            
            guard !Task.isCancelled else { return }
            
            // Cancel the debounce task since we're done loading
            loadingDebounceTask?.cancel()
            showLoading = false
            
            if let loadedImage = result.image {
                image = loadedImage
                errorMessage = nil
            } else {
                image = nil
                errorMessage = result.error ?? "Unknown error"
            }
        }
    }
    
    /// Schedule aggressive preloading with priority
    private func schedulePreloading(around index: Int, previousIndex: Int?) {
        preloadTask?.cancel()
        
        let photos = photoStore.photos
        let count = photos.count
        let cache = imageCache
        let maxDim = displayMaxDimension
        
        guard count > 0 else { return }
        
        // Determine scroll direction
        let scrollingForward = previousIndex == nil || index > previousIndex!
        
        preloadTask = Task.detached(priority: .userInitiated) {
            var requests: [PreloadRequest] = []
            
            // Priority 1: Immediately adjacent (critical for arrow key navigation)
            if scrollingForward {
                // Forward: prioritize next
                if index + 1 < count {
                    requests.append(PreloadRequest(path: photos[index + 1].path, priority: .high, maxDimension: maxDim))
                }
                if index - 1 >= 0 {
                    requests.append(PreloadRequest(path: photos[index - 1].path, priority: .high, maxDimension: maxDim))
                }
            } else {
                // Backward: prioritize previous
                if index - 1 >= 0 {
                    requests.append(PreloadRequest(path: photos[index - 1].path, priority: .high, maxDimension: maxDim))
                }
                if index + 1 < count {
                    requests.append(PreloadRequest(path: photos[index + 1].path, priority: .high, maxDimension: maxDim))
                }
            }
            
            // Priority 2: Nearby (2-5)
            for offset in 2...5 {
                if scrollingForward {
                    if index + offset < count {
                        requests.append(PreloadRequest(path: photos[index + offset].path, priority: .medium, maxDimension: maxDim))
                    }
                    if index - offset >= 0 {
                        requests.append(PreloadRequest(path: photos[index - offset].path, priority: .medium, maxDimension: maxDim))
                    }
                } else {
                    if index - offset >= 0 {
                        requests.append(PreloadRequest(path: photos[index - offset].path, priority: .medium, maxDimension: maxDim))
                    }
                    if index + offset < count {
                        requests.append(PreloadRequest(path: photos[index + offset].path, priority: .medium, maxDimension: maxDim))
                    }
                }
            }
            
            // Priority 3: Far ahead/behind (6-15)
            for offset in 6...15 {
                if scrollingForward {
                    if index + offset < count {
                        requests.append(PreloadRequest(path: photos[index + offset].path, priority: .low, maxDimension: maxDim))
                    }
                } else {
                    if index - offset >= 0 {
                        requests.append(PreloadRequest(path: photos[index - offset].path, priority: .low, maxDimension: maxDim))
                    }
                }
            }
            
            // Execute preloading
            await cache.preloadImages(requests: requests)
        }
    }
}

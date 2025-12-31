/**
 * PhotoDisplayView.swift
 * Main photo display with zoom and pan - fills container
 * Includes image preloading and debounced loading indicator
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
        let cache = imageCache
        
        // Check cache first
        Task {
            if let cached = await cache.fullSizeImage(for: path) {
                image = cached
                errorMessage = nil
                resetZoom()
                return
            }
            
            startLoading(path: path)
        }
    }
    
    private func resetZoom() {
        scale = 1.0
        offset = .zero
        lastOffset = .zero
    }
    
    private func startLoading(path: String) {
        errorMessage = nil
        resetZoom()
        
        let cache = imageCache
        
        // Debounce loading indicator - only show after 150ms
        loadingDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            if !Task.isCancelled {
                showLoading = true
            }
        }
        
        // Load image using the unified cache manager
        loadingTask = Task {
            let result = await cache.loadFullSizeImage(at: path)
            
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
    
    private func preloadAdjacentImages(around index: Int) {
        // Capture the photos array and cache reference
        let photos = photoStore.photos
        let count = photos.count
        let preloadRange = 5
        let cache = imageCache
        
        Task.detached(priority: .utility) {
            // Preload next images
            for preloadOffset in 1...preloadRange {
                let nextIndex = index + preloadOffset
                if nextIndex < count {
                    let path = photos[nextIndex].path
                    let cached = await cache.fullSizeImage(for: path)
                    if cached == nil {
                        let result = await loadImageFromDisk(at: path)
                        if let img = result.image {
                            await cache.setFullSizeImage(img, for: path)
                        }
                    }
                }
            }
            
            // Preload previous images
            for preloadOffset in 1...preloadRange {
                let prevIndex = index - preloadOffset
                if prevIndex >= 0 {
                    let path = photos[prevIndex].path
                    let cached = await cache.fullSizeImage(for: path)
                    if cached == nil {
                        let result = await loadImageFromDisk(at: path)
                        if let img = result.image {
                            await cache.setFullSizeImage(img, for: path)
                        }
                    }
                }
            }
        }
    }
}

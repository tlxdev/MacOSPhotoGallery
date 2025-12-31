/**
 * PhotoGridView.swift
 * Ultra-optimized photo grid with instant thumbnail loading
 * 
 * Optimizations:
 * - Batch thumbnail prefetching for visible + buffer area
 * - High-priority loading for visible cells
 * - Large thumbnail cache (2000 items)
 */

import SwiftUI
import AppKit

struct PhotoGridView: View {
    @Environment(PhotoStore.self) private var photoStore
    @Environment(\.imageCache) private var imageCache
    
    private let spacing: CGFloat = 4
    private let padding: CGFloat = 4
    private let minCellSize: CGFloat = 150
    
    // Prefetch buffer - how many rows ahead/behind to prefetch
    private let prefetchBuffer = 3
    
    var body: some View {
        @Bindable var photoStore = photoStore
        
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - (padding * 2)
            let columnsCount = max(2, Int(availableWidth / minCellSize))
            let totalSpacing = spacing * CGFloat(columnsCount - 1)
            let cellSize = (availableWidth - totalSpacing) / CGFloat(columnsCount)
            let thumbnailSize = cellSize * 2 // Retina
            
            let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: columnsCount)
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(Array(photoStore.photos.enumerated()), id: \.element.id) { index, photo in
                            PhotoGridCell(photo: photo, isSelected: index == photoStore.selectedIndex, size: cellSize, imageCache: imageCache)
                                .id(photo.id)
                                .onTapGesture {
                                    photoStore.select(index: index)
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        photoStore.isGridVisible = false
                                    }
                                }
                                .onAppear {
                                    // Prefetch thumbnails when cell appears
                                    prefetchThumbnails(around: index, columnsCount: columnsCount, thumbnailSize: thumbnailSize)
                                }
                        }
                    }
                    .padding(padding)
                }
                .onChange(of: photoStore.selectedIndex) { _, newIndex in
                    if newIndex < photoStore.photos.count {
                        withAnimation {
                            proxy.scrollTo(photoStore.photos[newIndex].id, anchor: .center)
                        }
                    }
                }
                .onAppear {
                    // Initial prefetch for first visible items
                    prefetchInitialThumbnails(columnsCount: columnsCount, viewHeight: geometry.size.height, cellSize: cellSize, thumbnailSize: thumbnailSize)
                }
            }
        }
    }
    
    /// Prefetch thumbnails around a visible cell
    private func prefetchThumbnails(around index: Int, columnsCount: Int, thumbnailSize: CGFloat) {
        let photos = photoStore.photos
        let count = photos.count
        let cache = imageCache
        
        // Calculate how many items to prefetch (buffer rows * columns)
        let prefetchCount = prefetchBuffer * columnsCount
        
        Task.detached(priority: .medium) {
            var paths: [String] = []
            
            // Prefetch ahead
            for i in 0..<prefetchCount {
                let nextIndex = index + i
                if nextIndex < count {
                    paths.append(photos[nextIndex].path)
                }
            }
            
            // Prefetch behind (less aggressive)
            for i in 1..<(prefetchCount / 2) {
                let prevIndex = index - i
                if prevIndex >= 0 {
                    paths.append(photos[prevIndex].path)
                }
            }
            
            await cache.prefetchThumbnails(paths: paths, size: thumbnailSize)
        }
    }
    
    /// Initial prefetch when grid appears
    private func prefetchInitialThumbnails(columnsCount: Int, viewHeight: CGFloat, cellSize: CGFloat, thumbnailSize: CGFloat) {
        let photos = photoStore.photos
        let cache = imageCache
        
        // Calculate visible rows + buffer
        let visibleRows = Int(ceil(viewHeight / (cellSize + spacing))) + prefetchBuffer
        let itemsToLoad = visibleRows * columnsCount
        
        Task.detached(priority: .userInitiated) {
            let paths = photos.prefix(itemsToLoad).map(\.path)
            await cache.prefetchThumbnails(paths: Array(paths), size: thumbnailSize)
        }
    }
}

struct PhotoGridCell: View {
    let photo: PhotoItem
    let isSelected: Bool
    let size: CGFloat
    let imageCache: ImageCacheManager
    
    @State private var thumbnail: NSImage?
    @State private var isLoading = true
    @State private var isHovering = false
    
    var body: some View {
        ZStack {
            // Dark background
            Rectangle()
                .fill(Color(white: 0.08))
            
            // Thumbnail - fills entire cell
            if let thumb = thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
            } else if isLoading {
                // Subtle shimmer placeholder instead of spinner for smoother feel
                Rectangle()
                    .fill(Color(white: 0.12))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.white.opacity(0.15))
            }
            
            // Selection overlay
            if isSelected {
                Rectangle()
                    .strokeBorder(.cyan, lineWidth: 3)
            }
            
            // Hover overlay
            if isHovering && !isSelected {
                Rectangle()
                    .strokeBorder(.white.opacity(0.4), lineWidth: 2)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .onHover { hovering in
            isHovering = hovering
        }
        .task(id: photo.id) {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        let path = photo.path
        let thumbnailSize = size * 2 // Retina
        
        // Check cache first
        if let cached = await imageCache.thumbnail(for: path) {
            thumbnail = cached
            isLoading = false
            return
        }
        
        // Generate thumbnail with high priority since we're visible
        let thumb = await imageCache.generateThumbnail(for: path, size: thumbnailSize)
        
        thumbnail = thumb
        isLoading = false
    }
}

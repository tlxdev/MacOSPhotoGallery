/**
 * PhotoGridView.swift
 * Photo grid with glass-effect thumbnails - fills container 100%
 */

import SwiftUI
import AppKit

struct PhotoGridView: View {
    @EnvironmentObject var photoStore: PhotoStore
    
    let spacing: CGFloat = 4
    let padding: CGFloat = 4
    let minCellSize: CGFloat = 150
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - (padding * 2)
            let columnsCount = max(2, Int(availableWidth / minCellSize))
            let totalSpacing = spacing * CGFloat(columnsCount - 1)
            let cellSize = (availableWidth - totalSpacing) / CGFloat(columnsCount)
            
            let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: columnsCount)
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(Array(photoStore.photos.enumerated()), id: \.element.id) { index, photo in
                            PhotoGridCell(photo: photo, isSelected: index == photoStore.selectedIndex, size: cellSize)
                                .id(photo.id)
                                .onTapGesture {
                                    photoStore.select(index: index)
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        photoStore.isGridVisible = false
                                    }
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
            }
        }
    }
}

struct PhotoGridCell: View {
    let photo: PhotoItem
    let isSelected: Bool
    let size: CGFloat
    
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
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white.opacity(0.4))
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
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        let path = photo.path
        let thumbnailSize = max(size * 2, 400) // Retina, minimum 400px
        
        DispatchQueue.global(qos: .userInitiated).async {
            let thumb = Self.generateThumbnail(for: path, size: thumbnailSize)
            
            DispatchQueue.main.async {
                self.thumbnail = thumb
                self.isLoading = false
            }
        }
    }
    
    private static nonisolated func generateThumbnail(for path: String, size: CGFloat) -> NSImage? {
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

/**
 * PhotoGridView.swift
 * Photo grid with glass-effect thumbnails - fills container 100%
 */

import SwiftUI
import AppKit

struct PhotoGridView: View {
    @EnvironmentObject var photoStore: PhotoStore
    
    private let spacing: CGFloat = 4
    private let padding: CGFloat = 4
    private let minCellSize: CGFloat = 150
    
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
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        let path = photo.path
        let thumbnailSize = max(size * 2, 400) // Retina, minimum 400px
        
        let thumb = await ImageCacheManager.shared.generateThumbnail(for: path, size: thumbnailSize)
        
        await MainActor.run {
            self.thumbnail = thumb
            self.isLoading = false
        }
    }
}

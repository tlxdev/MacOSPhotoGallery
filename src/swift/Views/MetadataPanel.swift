/**
 * MetadataPanel.swift
 * Glass sidebar showing photo metadata and EXIF info
 */

import SwiftUI

struct MetadataPanel: View {
    @Environment(PhotoStore.self) private var photoStore
    @State private var photo: PhotoItem?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let photo = photo {
                    metadataContent(for: photo)
                } else {
                    emptyState
                }
            }
            .padding(20)
        }
        .background {
            // Glass panel background
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.5))
                .overlay {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.08), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
        }
        .overlay(alignment: .leading) {
            // Left edge highlight
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1)
        }
        .onChange(of: photoStore.selectedIndex) { _, _ in
            loadCurrentPhoto()
        }
        .onChange(of: photoStore.photos) { _, _ in
            loadCurrentPhoto()
        }
        .onAppear {
            loadCurrentPhoto()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.white.opacity(0.2))
            
            Text("No photo selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
    
    private func metadataContent(for photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // File name header
            VStack(alignment: .leading, spacing: 8) {
                Text(photo.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                
                Text(photo.path)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            GlassDivider()
            
            // File info
            MetadataSection(title: "FILE") {
                MetadataRow(label: "Size", value: PhotoItem.formattedFileSize(photo.fileSize))
                MetadataRow(label: "Created", value: DateFormatters.formatForDisplay(photo.createdDate))
                MetadataRow(label: "Modified", value: DateFormatters.formatForDisplay(photo.modifiedDate))
            }
            
            // Image info
            if photo.dimensions.width > 0 {
                GlassDivider()
                
                MetadataSection(title: "IMAGE") {
                    MetadataRow(
                        label: "Dimensions",
                        value: "\(Int(photo.dimensions.width)) x \(Int(photo.dimensions.height))"
                    )
                    if let colorSpace = photo.colorSpace {
                        MetadataRow(label: "Color Space", value: colorSpace)
                    }
                    if let dateTaken = photo.dateTaken {
                        MetadataRow(label: "Date Taken", value: DateFormatters.formatForDisplay(dateTaken))
                    }
                }
            }
            
            // Camera info
            if photo.cameraMake != nil || photo.cameraModel != nil {
                GlassDivider()
                
                MetadataSection(title: "CAMERA") {
                    if let make = photo.cameraMake {
                        MetadataRow(label: "Make", value: make)
                    }
                    if let model = photo.cameraModel {
                        MetadataRow(label: "Model", value: model)
                    }
                }
            }
            
            // Exposure info
            if photo.exposureTime != nil || photo.fNumber != nil || photo.iso != nil || photo.focalLength != nil {
                GlassDivider()
                
                MetadataSection(title: "EXPOSURE") {
                    if let exposure = photo.exposureTime {
                        MetadataRow(label: "Shutter", value: exposure)
                    }
                    if let aperture = photo.fNumber {
                        MetadataRow(label: "Aperture", value: aperture)
                    }
                    if let iso = photo.iso {
                        MetadataRow(label: "ISO", value: "\(iso)")
                    }
                    if let focal = photo.focalLength {
                        MetadataRow(label: "Focal Length", value: focal)
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private func loadCurrentPhoto() {
        if var currentPhoto = photoStore.currentPhoto {
            currentPhoto.loadMetadata()
            photo = currentPhoto
        } else {
            photo = nil
        }
    }
}

struct MetadataSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(1.5)
            
            content
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.trailing)
        }
    }
}

struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.15), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}

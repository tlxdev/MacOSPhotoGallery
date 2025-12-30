/**
 * WelcomeView.swift
 * Welcome screen with Liquid Glass design
 */

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var photoStore: PhotoStore
    @State private var isHovering = false
    @State private var appeared = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Main glass card
            VStack(spacing: 32) {
                // Icon with glow
                ZStack {
                    // Glow effect
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blur(radius: 30)
                        .opacity(0.6)
                    
                    // Main icon
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.cyan, .blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .cyan.opacity(0.3), radius: 20)
                }
                .scaleEffect(appeared ? 1 : 0.8)
                .opacity(appeared ? 1 : 0)
                
                // Title and subtitle
                VStack(spacing: 12) {
                    Text("PhotoViewer")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("High-performance viewing for your photo library")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .offset(y: appeared ? 0 : 10)
                .opacity(appeared ? 1 : 0)
                
                // Open button with glass effect
                Button(action: { photoStore.openFolderPanel() }) {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 16, weight: .medium))
                        Text("Open Folder")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        .linearGradient(
                                            colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            }
                            .shadow(color: .cyan.opacity(isHovering ? 0.4 : 0.2), radius: isHovering ? 20 : 10)
                    }
                    .scaleEffect(isHovering ? 1.05 : 1)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isHovering = hovering
                    }
                }
                .offset(y: appeared ? 0 : 15)
                .opacity(appeared ? 1 : 0)
                
                // Recents section
                if !photoStore.recentFolders.isEmpty {
                    recentsSection
                        .offset(y: appeared ? 0 : 20)
                        .opacity(appeared ? 1 : 0)
                }
                
                // Keyboard hints
                keyboardHints
                    .offset(y: appeared ? 0 : 25)
                    .opacity(appeared ? 1 : 0)
            }
            .padding(48)
            .background {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(
                                .linearGradient(
                                    colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.3), radius: 40, y: 20)
            }
            
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
        }
    }
    
    private var recentsSection: some View {
        VStack(spacing: 16) {
            Text("Recent Folders")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(1)
            
            VStack(spacing: 8) {
                ForEach(photoStore.recentFolders.prefix(5), id: \.self) { path in
                    RecentFolderButton(path: path) {
                        photoStore.openFolder(at: path)
                    }
                }
            }
        }
        .padding(.top, 8)
    }
    
    private var keyboardHints: some View {
        HStack(spacing: 24) {
            KeyHint(key: "Arrow keys", action: "Navigate")
            KeyHint(key: "G", action: "Grid")
            KeyHint(key: "I", action: "Info")
        }
        .padding(.top, 16)
    }
}

struct RecentFolderButton: View {
    let path: String
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.cyan.opacity(0.8))
                
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.1 : 0.05))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

struct KeyHint: View {
    let key: String
    let action: String
    
    var body: some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.1))
                }
            
            Text(action)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}


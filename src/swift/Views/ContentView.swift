/**
 * ContentView.swift
 * Main content view - unified title bar with content
 */

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var photoStore: PhotoStore
    @State private var indexInput: String = "1"
    @State private var eventMonitor: Any?
    @FocusState private var isIndexFieldFocused: Bool
    
    var body: some View {
        ZStack {
            // Deep background
            Color(red: 0.02, green: 0.02, blue: 0.035)
                .ignoresSafeArea()
            
            // Content
            if photoStore.photos.isEmpty && !photoStore.isScanning {
                WelcomeView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                mainContent
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: photoStore.photos.isEmpty)
        .onAppear {
            setupKeyboardHandling()
            AppLogger.info("ContentView appeared", category: .ui)
        }
        .onDisappear {
            cleanupKeyboardHandling()
            AppLogger.info("ContentView disappeared", category: .ui)
        }
        .onChange(of: photoStore.selectedIndex) { _, newIndex in
            // Sync input field when index changes externally
            if !isIndexFieldFocused {
                indexInput = "\(newIndex + 1)"
            }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Title bar - same height as traffic lights area
            titleBar
            
            // Main content area
            HStack(spacing: 0) {
                // Photo display
                ZStack {
                    if photoStore.isGridVisible {
                        PhotoGridView()
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                removal: .opacity
                            ))
                    } else {
                        PhotoDisplayView()
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 1.02)),
                                removal: .opacity
                            ))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: photoStore.isGridVisible)
                
                // Info panel
                if photoStore.isInfoVisible {
                    MetadataPanel()
                        .frame(width: 280)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: photoStore.isInfoVisible)
        }
    }
    
    private var titleBar: some View {
        HStack(spacing: 12) {
            // Left: Space for traffic lights (they're ~70px from left edge)
            Color.clear
                .frame(width: 78)
            
            // Folder button
            Button(action: { photoStore.openFolderPanel() }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11, weight: .medium))
                    Text(photoStore.folderName ?? "Open Folder")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(.white.opacity(0.08))
                }
            }
            .buttonStyle(.plain)
            
            // Photo count
            if photoStore.photoCount > 0 {
                Text("\(photoStore.photoCount) photos")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
            
            Spacer()
            
            // Center: Navigation with editable index
            if photoStore.photoCount > 0 {
                navigationControl
            }
            
            Spacer()
            
            // Right: Actions
            HStack(spacing: 2) {
                titleBarButton(icon: "square.grid.2x2", isActive: photoStore.isGridVisible) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        photoStore.isGridVisible.toggle()
                    }
                }
                
                titleBarButton(icon: "info.circle", isActive: photoStore.isInfoVisible) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        photoStore.isInfoVisible.toggle()
                    }
                }
                
                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 6)
                
                titleBarButton(icon: "arrow.up.forward.square") {
                    photoStore.showInFinder()
                }
                
                titleBarButton(icon: "square.and.arrow.up") {
                    shareCurrentPhoto()
                }
            }
            .padding(.trailing, 12)
        }
        .frame(height: 38)
        .background {
            Color(red: 0.02, green: 0.02, blue: 0.035)
        }
    }
    
    private var navigationControl: some View {
        HStack(spacing: 3) {
            // Editable index field
            TextField("", text: $indexInput)
                .focused($isIndexFieldFocused)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.trailing)
                .frame(width: max(30, CGFloat(String(photoStore.photoCount).count) * 9))
                .textFieldStyle(.plain)
                .onSubmit {
                    jumpToIndex()
                }
                .onChange(of: isIndexFieldFocused) { _, focused in
                    if focused {
                        // Select all text when focused
                        DispatchQueue.main.async {
                            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                        }
                    } else {
                        // Reset to current index when focus lost
                        indexInput = "\(photoStore.selectedIndex + 1)"
                    }
                }
            
            Text("/")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
            
            Text("\(photoStore.photoCount)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(isIndexFieldFocused ? 0.1 : 0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.white.opacity(isIndexFieldFocused ? 0.2 : 0), lineWidth: 1)
                }
        }
    }
    
    private func jumpToIndex() {
        // Parse input and navigate
        guard let number = Int(indexInput.trimmingCharacters(in: .whitespaces)) else {
            // Invalid input, reset to current
            indexInput = "\(photoStore.selectedIndex + 1)"
            return
        }
        
        // Clamp to valid range (1-based input)
        let targetIndex = max(0, min(number - 1, photoStore.photoCount - 1))
        photoStore.select(index: targetIndex)
        indexInput = "\(targetIndex + 1)"
        isIndexFieldFocused = false
    }
    
    private func titleBarButton(icon: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? .cyan : .white.opacity(0.55))
                .frame(width: 26, height: 26)
                .background {
                    Circle()
                        .fill(.white.opacity(isActive ? 0.12 : 0))
                }
        }
        .buttonStyle(.plain)
    }
    
    private func shareCurrentPhoto() {
        guard let photo = photoStore.currentPhoto else { return }
        
        let url = URL(fileURLWithPath: photo.path)
        let sharingPicker = NSSharingServicePicker(items: [url])
        
        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            sharingPicker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }
    
    private func setupKeyboardHandling() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Don't intercept if text field is focused
            guard !isIndexFieldFocused else { return event }
            guard !photoStore.photos.isEmpty else { return event }
            
            switch event.keyCode {
            case 123: // Left arrow
                photoStore.selectPrevious()
                return nil
            case 124: // Right arrow
                photoStore.selectNext()
                return nil
            case 5: // G key
                if !event.modifierFlags.contains(.command) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        photoStore.isGridVisible.toggle()
                    }
                    return nil
                }
            case 34: // I key
                if !event.modifierFlags.contains(.command) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        photoStore.isInfoVisible.toggle()
                    }
                    return nil
                }
            case 8: // C key
                if event.modifierFlags.contains(.command) {
                    photoStore.copyCurrentPhoto()
                    return nil
                }
            case 53: // Escape
                return nil
            default:
                break
            }
            return event
        }
        AppLogger.debug("Keyboard event monitor installed", category: .ui)
    }
    
    private func cleanupKeyboardHandling() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
            AppLogger.debug("Keyboard event monitor removed", category: .ui)
        }
    }
}

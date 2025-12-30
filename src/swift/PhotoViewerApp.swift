/**
 * PhotoViewerApp.swift
 * Main app entry point with SwiftUI lifecycle
 */

import SwiftUI

@main
struct PhotoViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var photoStore = PhotoStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(photoStore)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder...") {
                    photoStore.openFolderPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            
            CommandGroup(after: .newItem) {
                Menu("Open Recent") {
                    ForEach(photoStore.recentFolders, id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) {
                            photoStore.openFolder(at: path)
                        }
                    }
                    
                    if !photoStore.recentFolders.isEmpty {
                        Divider()
                        Button("Clear Recents") {
                            photoStore.clearRecents()
                        }
                    }
                }
            }
            
            CommandGroup(replacing: .toolbar) {
                Button("Toggle Grid View") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        photoStore.isGridVisible.toggle()
                    }
                }
                .keyboardShortcut("g", modifiers: [])
                
                Button("Toggle Info Panel") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        photoStore.isInfoVisible.toggle()
                    }
                }
                .keyboardShortcut("i", modifiers: [])
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure app appearance
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

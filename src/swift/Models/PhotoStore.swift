/**
 * PhotoStore.swift
 * Central store managing photo collection, selection, and state
 * Bridges to C scanner for high-performance directory scanning
 */

import Foundation
import AppKit
import Combine

@MainActor
class PhotoStore: ObservableObject {
    // MARK: - Published State
    @Published private(set) var photos: [PhotoItem] = []
    @Published var selectedIndex: Int = 0
    @Published private(set) var folderPath: String?
    @Published private(set) var isScanning: Bool = false
    @Published var isGridVisible: Bool = false
    @Published var isInfoVisible: Bool = false
    @Published private(set) var recentFolders: [String] = []
    @Published private(set) var errorMessage: String?
    
    // MARK: - Computed Properties
    var photoCount: Int { photos.count }
    var folderName: String? { folderPath.map { URL(fileURLWithPath: $0).lastPathComponent } }
    var currentPhoto: PhotoItem? {
        guard selectedIndex >= 0, selectedIndex < photos.count else { return nil }
        return photos[selectedIndex]
    }
    
    // MARK: - Private
    private let userDefaultsKey = "RecentFolders"
    private let maxRecents = 10
    private var fileMonitor: DispatchSourceFileSystemObject?
    
    // MARK: - Initialization
    init() {
        loadRecents()
    }
    
    // MARK: - Folder Operations
    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder containing photos"
        panel.prompt = "Open"
        
        if panel.runModal() == .OK, let url = panel.url {
            openFolder(at: url.path)
        }
    }
    
    func openFolder(at path: String) {
        guard !isScanning else { return }
        
        // Validate path
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isReadableFile(atPath: path) else {
            errorMessage = "Cannot access folder: \(path)"
            return
        }
        
        isScanning = true
        errorMessage = nil
        folderPath = path
        
        Task { [weak self] in
            guard let self = self else { return }
            let scannedPhotos = self.scanDirectory(path: path)
            
            self.photos = scannedPhotos
            self.selectedIndex = 0
            self.isScanning = false
            self.addToRecents(path)
        }
    }
    
    private nonisolated func scanDirectory(path: String) -> [PhotoItem] {
        guard let collection = pv_collection_create() else {
            return []
        }
        defer { pv_collection_free(collection) }
        
        let count = pv_scan_directory(collection, path)
        guard count > 0 else { return [] }
        
        var items: [PhotoItem] = []
        items.reserveCapacity(Int(collection.pointee.count))
        
        for i in 0..<collection.pointee.count {
            guard let photo = pv_collection_get(collection, i) else { continue }
            
            // Access the C struct fields safely using withUnsafePointer
            let photoPath = withUnsafePointer(to: photo.pointee.path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(PV_MAX_PATH)) { charPtr in
                    String(cString: charPtr)
                }
            }
            
            let photoName = withUnsafePointer(to: photo.pointee.name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 256) { charPtr in
                    String(cString: charPtr)
                }
            }
            
            let item = PhotoItem(
                path: photoPath,
                name: photoName,
                fileSize: photo.pointee.size,
                createdDate: Date(timeIntervalSince1970: TimeInterval(photo.pointee.created_time)),
                modifiedDate: Date(timeIntervalSince1970: TimeInterval(photo.pointee.modified_time)),
                index: Int(i)
            )
            items.append(item)
        }
        
        return items
    }
    
    // MARK: - Navigation
    func selectNext() {
        guard selectedIndex < photos.count - 1 else { return }
        selectedIndex += 1
    }
    
    func selectPrevious() {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
    }
    
    func select(index: Int) {
        guard index >= 0, index < photos.count else { return }
        selectedIndex = index
    }
    
    // MARK: - Recents
    private func loadRecents() {
        guard let saved = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] else {
            return
        }
        
        // Filter out paths that no longer exist
        let fileManager = FileManager.default
        recentFolders = saved.filter { path in
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
    }
    
    private func addToRecents(_ path: String) {
        var recents = recentFolders.filter { $0 != path }
        recents.insert(path, at: 0)
        if recents.count > maxRecents {
            recents = Array(recents.prefix(maxRecents))
        }
        recentFolders = recents
        UserDefaults.standard.set(recents, forKey: userDefaultsKey)
    }
    
    func clearRecents() {
        recentFolders = []
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
    
    // MARK: - Photo Operations
    func loadMetadata(for index: Int) {
        guard index >= 0, index < photos.count else { return }
        photos[index].loadMetadata()
    }
    
    func copyCurrentPhoto() {
        guard let photo = currentPhoto else { return }
        
        let url = URL(fileURLWithPath: photo.path)
        guard let image = NSImage(contentsOf: url) else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    
    func showInFinder() {
        guard let photo = currentPhoto else { return }
        NSWorkspace.shared.selectFile(photo.path, inFileViewerRootedAtPath: "")
    }
}


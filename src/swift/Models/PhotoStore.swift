/**
 * PhotoStore.swift
 * Central store managing photo collection, selection, and state
 * Bridges to C scanner for high-performance directory scanning
 * Uses @Observable for modern SwiftUI integration
 */

import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class PhotoStore {
    // MARK: - Observable State
    private(set) var photos: [PhotoItem] = []
    var selectedIndex: Int = 0
    private(set) var folderPath: String?
    private(set) var isScanning: Bool = false
    var isGridVisible: Bool = false
    var isInfoVisible: Bool = false
    private(set) var recentFolders: [String] = []
    private(set) var errorMessage: String?
    
    // State for SwiftUI fileImporter
    var isFileImporterPresented: Bool = false
    
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
    
    // MARK: - Initialization
    init() {
        loadRecents()
        AppLogger.info("PhotoStore initialized", category: .photoStore)
    }
    
    // MARK: - Folder Operations
    
    /// Presents the file importer (called from views)
    func presentFolderPicker() {
        isFileImporterPresented = true
    }
    
    /// Handle folder selection from fileImporter
    func handleFolderSelection(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Cannot access folder: permission denied"
                AppLogger.error("Failed to access security-scoped resource: \(url.path)", category: .photoStore)
                return
            }
            
            // Open the folder
            openFolder(at: url.path)
            
            // Stop accessing when done (defer would be too early)
            // We keep access since we need to read files within
            
        case .failure(let error):
            errorMessage = "Failed to open folder: \(error.localizedDescription)"
            AppLogger.error("File importer error: \(error)", category: .photoStore)
        }
    }
    
    func openFolder(at path: String) {
        guard !isScanning else {
            AppLogger.warning("Scan already in progress, ignoring request", category: .photoStore)
            return
        }
        
        // Validate path
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isReadableFile(atPath: path) else {
            errorMessage = "Cannot access folder: \(path)"
            AppLogger.error("Cannot access folder: \(path)", category: .photoStore)
            return
        }
        
        isScanning = true
        errorMessage = nil
        folderPath = path
        AppLogger.info("Starting folder scan: \(path)", category: .photoStore)
        
        Task { [weak self] in
            guard let self = self else { return }
            let scannedPhotos = self.scanDirectory(path: path)
            
            self.photos = scannedPhotos
            self.selectedIndex = 0
            self.isScanning = false
            self.addToRecents(path)
            AppLogger.info("Scan complete: found \(scannedPhotos.count) photos", category: .photoStore)
        }
    }
    
    private nonisolated func scanDirectory(path: String) -> [PhotoItem] {
        guard let collection = pv_collection_create() else {
            AppLogger.error("Failed to create photo collection", category: .photoStore)
            return []
        }
        defer { pv_collection_free(collection) }
        
        let count = pv_scan_directory(collection, path)
        guard count > 0 else {
            AppLogger.info("No photos found in directory", category: .photoStore)
            return []
        }
        
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
        AppLogger.debug("Loaded \(recentFolders.count) recent folders", category: .photoStore)
    }
    
    private func addToRecents(_ path: String) {
        let recents = [path] + recentFolders.filter { $0 != path }.prefix(maxRecents - 1)
        recentFolders = Array(recents)
        UserDefaults.standard.set(recentFolders, forKey: userDefaultsKey)
    }
    
    func clearRecents() {
        recentFolders = []
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        AppLogger.info("Cleared recent folders", category: .photoStore)
    }
    
    // MARK: - Photo Operations
    func loadMetadata(for index: Int) {
        guard index >= 0, index < photos.count else { return }
        photos[index].loadMetadata()
    }
    
    func copyCurrentPhoto() {
        guard let photo = currentPhoto else { return }
        
        let url = URL(fileURLWithPath: photo.path)
        guard let image = NSImage(contentsOf: url) else {
            AppLogger.warning("Failed to load image for copy: \(photo.path)", category: .photoStore)
            return
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        AppLogger.debug("Copied photo to clipboard: \(photo.name)", category: .photoStore)
    }
    
    func showInFinder() {
        guard let photo = currentPhoto else { return }
        NSWorkspace.shared.selectFile(photo.path, inFileViewerRootedAtPath: "")
    }
    
    /// Returns the URL for sharing the current photo (for ShareLink)
    var currentPhotoURL: URL? {
        guard let photo = currentPhoto else { return nil }
        return URL(fileURLWithPath: photo.path)
    }
}

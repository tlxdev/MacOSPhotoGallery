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
        
        // Cancel any ongoing eager thumbnail generation from previous folder
        Task {
            await ImageCacheManager.shared.cancelEagerGeneration()
        }
        
        Task { [weak self] in
            guard let self = self else { return }
            let scannedPhotos = self.scanDirectory(path: path)
            
            self.photos = scannedPhotos
            self.selectedIndex = 0
            self.isScanning = false
            self.addToRecents(path)
            AppLogger.info("Scan complete: found \(scannedPhotos.count) photos", category: .photoStore)
            
            // Start eager thumbnail generation in background
            // This will pre-generate thumbnails so they're instant when grid opens
            if !scannedPhotos.isEmpty {
                let paths = scannedPhotos.map(\.path)
                let thumbnailSize: CGFloat = 320 // Standard grid thumbnail size
                
                AppLogger.debug("Starting eager thumbnail generation for \(paths.count) photos", category: .photoStore)
                
                Task.detached(priority: .utility) {
                    await ImageCacheManager.shared.startEagerThumbnailGeneration(
                        paths: paths,
                        size: thumbnailSize
                    )
                }
            }
        }
    }
    
    private nonisolated func scanDirectory(path: String) -> [PhotoItem] {
        AppLogger.debug("scanDirectory called with path: \(path)", category: .photoStore)
        
        // Create collection with error handling
        AppLogger.debug("Creating photo collection...", category: .photoStore)
        guard let collection = pv_collection_create() else {
            AppLogger.error("Failed to create photo collection - pv_collection_create returned nil", category: .photoStore)
            return []
        }
        AppLogger.debug("Photo collection created successfully", category: .photoStore)
        
        defer {
            AppLogger.debug("Freeing photo collection", category: .photoStore)
            pv_collection_free(collection)
        }
        
        // Scan directory with error handling
        AppLogger.debug("Starting pv_scan_directory...", category: .photoStore)
        let count = pv_scan_directory(collection, path)
        AppLogger.debug("pv_scan_directory returned: \(count)", category: .photoStore)
        
        if count < 0 {
            AppLogger.error("pv_scan_directory failed with error code: \(count)", category: .photoStore)
            return []
        }
        
        if count == 0 {
            AppLogger.info("No photos found in directory", category: .photoStore)
            return []
        }
        
        // Get photo count and build items
        let photoCount = pv_collection_count(collection)
        AppLogger.debug("Photo count from collection: \(photoCount)", category: .photoStore)
        
        var items: [PhotoItem] = []
        items.reserveCapacity(Int(photoCount))
        
        for i in 0..<photoCount {
            guard let photo = pv_collection_get(collection, i) else {
                AppLogger.warning("pv_collection_get returned nil for index \(i)", category: .photoStore)
                continue
            }
            
            // Use accessor functions for Swift compatibility
            guard let pathPtr = pv_photo_get_path(photo),
                  let namePtr = pv_photo_get_name(photo) else {
                AppLogger.warning("Failed to get path/name for photo at index \(i)", category: .photoStore)
                continue
            }
            
            let photoPath = String(cString: pathPtr)
            let photoName = String(cString: namePtr)
            
            // Validate the path is not empty
            if photoPath.isEmpty {
                AppLogger.warning("Empty path for photo at index \(i)", category: .photoStore)
                continue
            }
            
            let item = PhotoItem(
                path: photoPath,
                name: photoName,
                fileSize: pv_photo_get_size(photo),
                createdDate: Date(timeIntervalSince1970: TimeInterval(pv_photo_get_created_time(photo))),
                modifiedDate: Date(timeIntervalSince1970: TimeInterval(pv_photo_get_modified_time(photo))),
                index: Int(i)
            )
            items.append(item)
        }
        
        AppLogger.debug("Successfully built \(items.count) PhotoItems", category: .photoStore)
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

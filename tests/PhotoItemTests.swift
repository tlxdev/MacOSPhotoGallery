/**
 * PhotoItemTests.swift
 * Unit tests for PhotoItem model
 */

import Foundation

struct PhotoItemTests {
    static func runAll() async {
        await TestRunner.run(suite: "PhotoItem Tests") {
            testInitialization()
            testFormattedFileSize()
            testEquality()
            testHashing()
        }
    }
    
    static func testInitialization() {
        let now = Date()
        let item = PhotoItem(
            path: "/test/photo.jpg",
            name: "photo.jpg",
            fileSize: 1024,
            createdDate: now,
            modifiedDate: now,
            index: 0
        )
        
        TestRunner.assertEqual(item.path, "/test/photo.jpg", "Path is set correctly")
        TestRunner.assertEqual(item.name, "photo.jpg", "Name is set correctly")
        TestRunner.assertEqual(item.fileSize, 1024, "File size is set correctly")
        TestRunner.assertEqual(item.index, 0, "Index is set correctly")
        TestRunner.assert(!item.metadataLoaded, "Metadata not loaded initially")
        TestRunner.assertNotNil(item.id, "UUID is generated")
    }
    
    static func testFormattedFileSize() {
        // Test bytes
        TestRunner.assertEqual(PhotoItem.formattedFileSize(0), "0 B", "0 bytes formatted correctly")
        TestRunner.assertEqual(PhotoItem.formattedFileSize(512), "512 B", "512 bytes formatted correctly")
        
        // Test kilobytes
        TestRunner.assertEqual(PhotoItem.formattedFileSize(1024), "1.0 KB", "1 KB formatted correctly")
        TestRunner.assertEqual(PhotoItem.formattedFileSize(1536), "1.5 KB", "1.5 KB formatted correctly")
        
        // Test megabytes
        TestRunner.assertEqual(PhotoItem.formattedFileSize(1048576), "1.0 MB", "1 MB formatted correctly")
        TestRunner.assertEqual(PhotoItem.formattedFileSize(5242880), "5.0 MB", "5 MB formatted correctly")
        
        // Test gigabytes
        TestRunner.assertEqual(PhotoItem.formattedFileSize(1073741824), "1.0 GB", "1 GB formatted correctly")
        
        // Test terabytes
        TestRunner.assertEqual(PhotoItem.formattedFileSize(1099511627776), "1.0 TB", "1 TB formatted correctly")
    }
    
    static func testEquality() {
        let now = Date()
        let item1 = PhotoItem(
            path: "/test/photo.jpg",
            name: "photo.jpg",
            fileSize: 1024,
            createdDate: now,
            modifiedDate: now,
            index: 0
        )
        
        let item2 = PhotoItem(
            path: "/test/photo.jpg",
            name: "different_name.jpg",  // Different name but same path
            fileSize: 2048,               // Different size
            createdDate: now,
            modifiedDate: now,
            index: 1
        )
        
        let item3 = PhotoItem(
            path: "/test/different.jpg",  // Different path
            name: "photo.jpg",
            fileSize: 1024,
            createdDate: now,
            modifiedDate: now,
            index: 0
        )
        
        TestRunner.assert(item1 == item2, "Items with same path are equal")
        TestRunner.assert(item1 != item3, "Items with different paths are not equal")
    }
    
    static func testHashing() {
        let now = Date()
        let item1 = PhotoItem(
            path: "/test/photo.jpg",
            name: "photo.jpg",
            fileSize: 1024,
            createdDate: now,
            modifiedDate: now,
            index: 0
        )
        
        let item2 = PhotoItem(
            path: "/test/photo.jpg",
            name: "different.jpg",
            fileSize: 2048,
            createdDate: now,
            modifiedDate: now,
            index: 1
        )
        
        // Same path should have same hash
        var set = Set<PhotoItem>()
        set.insert(item1)
        
        TestRunner.assert(set.contains(item2), "Items with same path have same hash for Set lookup")
        TestRunner.assertEqual(set.count, 1, "Set contains only one item after inserting duplicate path")
    }
}


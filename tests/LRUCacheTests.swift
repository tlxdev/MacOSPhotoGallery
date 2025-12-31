/**
 * LRUCacheTests.swift
 * Unit tests for LRUCache
 */

import Foundation

struct LRUCacheTests {
    static func runAll() async {
        await TestRunner.run(suite: "LRUCache Tests") {
            await testBasicSetAndGet()
            await testLRUEviction()
            await testMoveToFrontOnAccess()
            await testClear()
            await testContains()
            await testRemove()
            await testCapacityOne()
        }
    }
    
    static func testBasicSetAndGet() async {
        let cache = LRUCache<String, Int>(maxSize: 5)
        
        await cache.set("a", value: 1)
        await cache.set("b", value: 2)
        await cache.set("c", value: 3)
        
        let a = await cache.get("a")
        let b = await cache.get("b")
        let c = await cache.get("c")
        let d = await cache.get("d")
        
        TestRunner.assertEqual(a, 1, "Get 'a' returns 1")
        TestRunner.assertEqual(b, 2, "Get 'b' returns 2")
        TestRunner.assertEqual(c, 3, "Get 'c' returns 3")
        TestRunner.assertNil(d, "Get 'd' returns nil for missing key")
    }
    
    static func testLRUEviction() async {
        let cache = LRUCache<String, Int>(maxSize: 3)
        
        // Fill cache
        await cache.set("a", value: 1)
        await cache.set("b", value: 2)
        await cache.set("c", value: 3)
        
        // Add one more, should evict 'a' (oldest)
        await cache.set("d", value: 4)
        
        let a = await cache.get("a")
        let b = await cache.get("b")
        let d = await cache.get("d")
        
        TestRunner.assertNil(a, "Oldest entry 'a' was evicted")
        TestRunner.assertNotNil(b, "Entry 'b' still exists")
        TestRunner.assertEqual(d, 4, "New entry 'd' was added")
    }
    
    static func testMoveToFrontOnAccess() async {
        let cache = LRUCache<String, Int>(maxSize: 3)
        
        // Fill cache
        await cache.set("a", value: 1)
        await cache.set("b", value: 2)
        await cache.set("c", value: 3)
        
        // Access 'a' to make it most recently used
        _ = await cache.get("a")
        
        // Add two more items, should evict 'b' and 'c' but not 'a'
        await cache.set("d", value: 4)
        await cache.set("e", value: 5)
        
        let a = await cache.get("a")
        let b = await cache.get("b")
        let c = await cache.get("c")
        
        TestRunner.assertNotNil(a, "Entry 'a' was accessed and not evicted")
        TestRunner.assertNil(b, "Entry 'b' was evicted (oldest after 'a' access)")
        TestRunner.assertNil(c, "Entry 'c' was evicted")
    }
    
    static func testClear() async {
        let cache = LRUCache<String, Int>(maxSize: 5)
        
        await cache.set("a", value: 1)
        await cache.set("b", value: 2)
        
        await cache.clear()
        
        let count = await cache.count
        let a = await cache.get("a")
        
        TestRunner.assertEqual(count, 0, "Cache count is 0 after clear")
        TestRunner.assertNil(a, "All entries cleared")
    }
    
    static func testContains() async {
        let cache = LRUCache<String, Int>(maxSize: 5)
        
        await cache.set("a", value: 1)
        
        let containsA = await cache.contains("a")
        let containsB = await cache.contains("b")
        
        TestRunner.assert(containsA, "Contains returns true for existing key")
        TestRunner.assert(!containsB, "Contains returns false for missing key")
    }
    
    static func testRemove() async {
        let cache = LRUCache<String, Int>(maxSize: 5)
        
        await cache.set("a", value: 1)
        await cache.set("b", value: 2)
        
        await cache.remove("a")
        
        let a = await cache.get("a")
        let b = await cache.get("b")
        let count = await cache.count
        
        TestRunner.assertNil(a, "Removed entry returns nil")
        TestRunner.assertNotNil(b, "Other entries unaffected")
        TestRunner.assertEqual(count, 1, "Count decremented after remove")
    }
    
    static func testCapacityOne() async {
        let cache = LRUCache<String, Int>(maxSize: 1)
        
        await cache.set("a", value: 1)
        await cache.set("b", value: 2)
        
        let a = await cache.get("a")
        let b = await cache.get("b")
        let count = await cache.count
        
        TestRunner.assertNil(a, "First entry evicted with capacity 1")
        TestRunner.assertEqual(b, 2, "Second entry exists")
        TestRunner.assertEqual(count, 1, "Count is 1")
    }
}


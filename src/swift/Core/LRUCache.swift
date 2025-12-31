/**
 * LRUCache.swift
 * High-performance LRU cache using doubly-linked list for O(1) operations
 */

import Foundation

/// Node for doubly-linked list used in LRU cache
private final class LRUNode<Key: Hashable, Value> {
    let key: Key
    var value: Value
    var prev: LRUNode?
    var next: LRUNode?
    
    init(key: Key, value: Value) {
        self.key = key
        self.value = value
    }
}

/// A thread-safe LRU cache with O(1) access, insertion, and eviction
/// Uses a doubly-linked list combined with a dictionary for efficient operations
actor LRUCache<Key: Hashable, Value> {
    private var cache: [Key: LRUNode<Key, Value>] = [:]
    private var head: LRUNode<Key, Value>?
    private var tail: LRUNode<Key, Value>?
    private let maxSize: Int
    
    init(maxSize: Int) {
        self.maxSize = maxSize
    }
    
    /// Get value for key, moving it to front (most recently used)
    func get(_ key: Key) -> Value? {
        guard let node = cache[key] else {
            return nil
        }
        moveToFront(node)
        return node.value
    }
    
    /// Set value for key, evicting oldest if at capacity
    func set(_ key: Key, value: Value) {
        if let existingNode = cache[key] {
            existingNode.value = value
            moveToFront(existingNode)
            return
        }
        
        let newNode = LRUNode(key: key, value: value)
        cache[key] = newNode
        addToFront(newNode)
        
        if cache.count > maxSize {
            evictOldest()
        }
    }
    
    /// Check if key exists in cache
    func contains(_ key: Key) -> Bool {
        cache[key] != nil
    }
    
    /// Remove specific key from cache
    func remove(_ key: Key) {
        guard let node = cache[key] else { return }
        removeNode(node)
        cache.removeValue(forKey: key)
    }
    
    /// Clear all entries
    func clear() {
        cache.removeAll()
        head = nil
        tail = nil
    }
    
    /// Current number of cached items
    var count: Int {
        cache.count
    }
    
    // MARK: - Private Linked List Operations
    
    private func moveToFront(_ node: LRUNode<Key, Value>) {
        guard node !== head else { return }
        removeNode(node)
        addToFront(node)
    }
    
    private func addToFront(_ node: LRUNode<Key, Value>) {
        node.next = head
        node.prev = nil
        head?.prev = node
        head = node
        
        if tail == nil {
            tail = node
        }
    }
    
    private func removeNode(_ node: LRUNode<Key, Value>) {
        let prevNode = node.prev
        let nextNode = node.next
        
        if let prev = prevNode {
            prev.next = nextNode
        } else {
            head = nextNode
        }
        
        if let next = nextNode {
            next.prev = prevNode
        } else {
            tail = prevNode
        }
        
        node.prev = nil
        node.next = nil
    }
    
    private func evictOldest() {
        guard let oldestNode = tail else { return }
        cache.removeValue(forKey: oldestNode.key)
        removeNode(oldestNode)
        AppLogger.debug("Evicted oldest cache entry", category: .imageCache)
    }
}


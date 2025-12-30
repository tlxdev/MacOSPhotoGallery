/**
 * photo_cache.c
 * LRU image cache implementation
 */

#include "photo_cache.h"
#include <stdlib.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>

/* Internal: Remove entry from list */
static void cache_unlink(pv_image_cache_t *cache, pv_cache_entry_t *entry) {
    if (entry->prev != NULL) {
        entry->prev->next = entry->next;
    } else {
        cache->head = entry->next;
    }
    
    if (entry->next != NULL) {
        entry->next->prev = entry->prev;
    } else {
        cache->tail = entry->prev;
    }
    
    entry->next = NULL;
    entry->prev = NULL;
}

/* Internal: Add entry to front of list */
static void cache_push_front(pv_image_cache_t *cache, pv_cache_entry_t *entry) {
    entry->next = cache->head;
    entry->prev = NULL;
    
    if (cache->head != NULL) {
        cache->head->prev = entry;
    }
    
    cache->head = entry;
    
    if (cache->tail == NULL) {
        cache->tail = entry;
    }
}

/* Internal: Free entry */
static void cache_free_entry(pv_cache_entry_t *entry) {
    if (entry == NULL) {
        return;
    }
    
    /* Release CoreFoundation/Objective-C object */
    if (entry->image_ref != NULL) {
        CFRelease(entry->image_ref);
    }
    
    free(entry);
}

/* Internal: Evict oldest entries */
static void cache_evict(pv_image_cache_t *cache) {
    while (cache->count > cache->max_entries || 
           (cache->max_memory > 0 && cache->total_memory > cache->max_memory)) {
        pv_cache_entry_t *victim = cache->tail;
        if (victim == NULL) {
            break;
        }
        
        cache_unlink(cache, victim);
        cache->count--;
        cache->total_memory -= victim->memory_size;
        cache_free_entry(victim);
    }
}

pv_image_cache_t *pv_cache_create(size_t max_entries, size_t max_memory) {
    pv_image_cache_t *cache = calloc(1, sizeof(pv_image_cache_t));
    if (cache == NULL) {
        return NULL;
    }
    
    cache->max_entries = max_entries > 0 ? max_entries : PV_CACHE_MAX_ENTRIES;
    cache->max_memory = max_memory;
    
    return cache;
}

void pv_cache_free(pv_image_cache_t *cache) {
    if (cache == NULL) {
        return;
    }
    
    pv_cache_clear(cache);
    free(cache);
}

void *pv_cache_get(pv_image_cache_t *cache, const char *path) {
    if (cache == NULL || path == NULL) {
        return NULL;
    }
    
    pv_cache_entry_t *entry = cache->head;
    while (entry != NULL) {
        if (strcmp(entry->path, path) == 0) {
            /* Move to front (LRU) */
            if (entry != cache->head) {
                cache_unlink(cache, entry);
                cache_push_front(cache, entry);
            }
            return entry->image_ref;
        }
        entry = entry->next;
    }
    
    return NULL;
}

void pv_cache_put(pv_image_cache_t *cache, const char *path, void *image_ref, size_t memory_size) {
    if (cache == NULL || path == NULL || image_ref == NULL) {
        return;
    }
    
    /* Check if already cached */
    void *existing = pv_cache_get(cache, path);
    if (existing != NULL) {
        return;
    }
    
    /* Create new entry */
    pv_cache_entry_t *entry = calloc(1, sizeof(pv_cache_entry_t));
    if (entry == NULL) {
        return;
    }
    
    strncpy(entry->path, path, sizeof(entry->path) - 1);
    entry->image_ref = image_ref;
    entry->memory_size = memory_size;
    
    /* Retain the image reference */
    CFRetain(image_ref);
    
    /* Add to cache */
    cache_push_front(cache, entry);
    cache->count++;
    cache->total_memory += memory_size;
    
    /* Evict if needed */
    cache_evict(cache);
}

void pv_cache_clear(pv_image_cache_t *cache) {
    if (cache == NULL) {
        return;
    }
    
    pv_cache_entry_t *entry = cache->head;
    while (entry != NULL) {
        pv_cache_entry_t *next = entry->next;
        cache_free_entry(entry);
        entry = next;
    }
    
    cache->head = NULL;
    cache->tail = NULL;
    cache->count = 0;
    cache->total_memory = 0;
}


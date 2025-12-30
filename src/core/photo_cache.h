/**
 * photo_cache.h
 * Image caching for performance optimization
 */

#ifndef PHOTO_CACHE_H
#define PHOTO_CACHE_H

#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Maximum cache entries */
#define PV_CACHE_MAX_ENTRIES 20

/* Cache entry */
typedef struct pv_cache_entry {
    char path[4096];
    void *image_ref;  /* CGImageRef or NSImage* */
    size_t memory_size;
    struct pv_cache_entry *next;
    struct pv_cache_entry *prev;
} pv_cache_entry_t;

/* LRU Image cache */
typedef struct {
    pv_cache_entry_t *head;
    pv_cache_entry_t *tail;
    size_t count;
    size_t max_entries;
    size_t total_memory;
    size_t max_memory;
} pv_image_cache_t;

/**
 * Create image cache
 * @param max_entries Maximum number of cached images
 * @param max_memory Maximum memory usage in bytes
 * @return New cache or NULL on failure
 */
pv_image_cache_t *pv_cache_create(size_t max_entries, size_t max_memory);

/**
 * Free cache and all entries
 * @param cache Cache to free
 */
void pv_cache_free(pv_image_cache_t *cache);

/**
 * Get cached image
 * @param cache The cache
 * @param path Image path
 * @return Cached image reference or NULL if not cached
 */
void *pv_cache_get(pv_image_cache_t *cache, const char *path);

/**
 * Add image to cache
 * @param cache The cache
 * @param path Image path
 * @param image_ref Image reference (retained by cache)
 * @param memory_size Approximate memory size
 */
void pv_cache_put(pv_image_cache_t *cache, const char *path, void *image_ref, size_t memory_size);

/**
 * Clear all cached images
 * @param cache The cache
 */
void pv_cache_clear(pv_image_cache_t *cache);

#ifdef __cplusplus
}
#endif

#endif /* PHOTO_CACHE_H */


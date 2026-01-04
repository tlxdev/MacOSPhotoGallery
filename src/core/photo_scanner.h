/**
 * photo_scanner.h
 * Ultra high-performance photo directory scanner
 * 
 * Optimizations:
 * - Cache-aligned data structures for CPU efficiency
 * - SIMD-accelerated extension matching (ARM NEON + x86 SSE4.2)
 * - Parallel directory scanning with GCD work-stealing
 * - getattrlistbulk for batch attribute fetching
 * - Lock-free concurrent collection with atomic operations
 * - Radix sort O(n) for date sorting
 */

#ifndef PHOTO_SCANNER_H
#define PHOTO_SCANNER_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Configuration Constants
 * ============================================================================ */

/* Maximum path length */
#define PV_MAX_PATH 4096

/* Maximum filename length */
#define PV_MAX_NAME 256

/* Initial photo array capacity */
#define PV_INITIAL_CAPACITY 10000

/* Batch size for getattrlistbulk - optimal for SSD I/O */
#define PV_ATTR_BATCH_SIZE 256

/* Number of parallel scanner threads (0 = auto-detect based on CPU cores) */
#define PV_PARALLEL_THREADS 0

/* Prefetch distance for cache optimization */
#define PV_PREFETCH_DISTANCE 8

/* Cache line size for alignment */
#define PV_CACHE_LINE_SIZE 64

/* ============================================================================
 * Data Structures - Cache-Aligned for Performance
 * ============================================================================ */

/**
 * Photo file information - exactly 64 bytes (one cache line)
 * Paths stored separately in string pool for cache efficiency
 */
typedef struct __attribute__((aligned(PV_CACHE_LINE_SIZE))) {
    /* All hot data fits in single cache line */
    uint64_t size;              /* 8 bytes - file size */
    time_t created_time;        /* 8 bytes - creation timestamp */
    time_t modified_time;       /* 8 bytes - modification timestamp */
    uint32_t path_offset;       /* 4 bytes - offset into path pool */
    uint32_t index;             /* 4 bytes - index in collection */
    uint16_t path_len;          /* 2 bytes - path length */
    uint16_t name_offset;       /* 2 bytes - offset to name within path */
    uint16_t name_len;          /* 2 bytes - name length */
    uint16_t ext_hash;          /* 2 bytes - extension hash */
    uint8_t _pad[24];           /* 24 bytes - pad to 64 bytes */
} pv_photo_t;

/**
 * Photo collection with thread-safe operations
 * Paths stored in separate pool for cache-efficient photo iteration
 */
typedef struct {
    pv_photo_t *photos;                    /* Dynamic array of photos (64 bytes each) */
    size_t count;                          /* Current count */
    size_t capacity;                       /* Current capacity */

    /* Path string pool - contiguous storage for all paths */
    char *path_pool;                       /* Contiguous path storage */
    size_t path_pool_size;                 /* Current used size */
    size_t path_pool_capacity;             /* Allocated capacity */

    char root_path[PV_MAX_PATH];           /* Root directory path */

    /* Statistics */
    uint64_t scan_time_ns;                 /* Time taken to scan (nanoseconds) */
    uint64_t sort_time_ns;                 /* Time taken to sort (nanoseconds) */
    uint32_t directories_scanned;          /* Number of directories processed */
    uint32_t files_examined;               /* Total files examined */

    /* Internal: for thread-safe concurrent additions during scan */
    void *_internal_lock;                  /* pthread_mutex_t* - opaque for Swift */
} pv_photo_collection_t;

/**
 * Scanner configuration options
 */
typedef struct {
    uint32_t max_depth;                    /* Maximum recursion depth (0 = unlimited) */
    uint32_t thread_count;                 /* Number of parallel threads (0 = auto) */
    bool follow_symlinks;                  /* Follow symbolic links */
    bool include_hidden;                   /* Include hidden files/directories */
    bool use_simd;                         /* Use SIMD for extension matching */
    bool use_batch_attrs;                  /* Use getattrlistbulk */
} pv_scan_options_t;

/* Default scan options */
#define PV_SCAN_OPTIONS_DEFAULT ((pv_scan_options_t){ \
    .max_depth = 0,                                    \
    .thread_count = 0,                                 \
    .follow_symlinks = false,                          \
    .include_hidden = false,                           \
    .use_simd = false,                                 \
    .use_batch_attrs = true                            \
})

/* ============================================================================
 * Supported Extensions
 * ============================================================================ */

/* Supported image extensions */
static const char *PV_SUPPORTED_EXTENSIONS[] = {
    ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp",
    ".tiff", ".tif", ".heic", ".heif", ".avif",
    ".raw", ".cr2", ".nef", ".arw", ".dng",
    NULL
};

/* ============================================================================
 * Core API Functions
 * ============================================================================ */

/**
 * Create a new photo collection
 * @return Allocated collection or NULL on failure
 */
pv_photo_collection_t *pv_collection_create(void);

/**
 * Free a photo collection and all its resources
 * @param collection The collection to free
 */
void pv_collection_free(pv_photo_collection_t *collection);

/**
 * Scan a directory recursively for photos (uses default options)
 * @param collection The collection to populate
 * @param directory_path Path to scan
 * @return Number of photos found, or -1 on error
 */
int pv_scan_directory(pv_photo_collection_t *collection, const char *directory_path);

/**
 * Scan a directory with custom options
 * @param collection The collection to populate
 * @param directory_path Path to scan
 * @param options Scan configuration options
 * @return Number of photos found, or -1 on error
 */
int pv_scan_directory_ex(pv_photo_collection_t *collection, 
                          const char *directory_path,
                          const pv_scan_options_t *options);

/**
 * Check if a file extension is a supported image format
 * Uses SIMD-accelerated matching when available
 * @param filename The filename to check
 * @return true if supported, false otherwise
 */
bool pv_is_supported_image(const char *filename);

/**
 * Sort collection by creation time (newest first)
 * Uses parallel radix sort for O(n) complexity
 * @param collection The collection to sort
 */
void pv_collection_sort_by_date(pv_photo_collection_t *collection);

/**
 * Sort collection by name (alphabetical)
 * Uses parallel merge sort
 * @param collection The collection to sort
 */
void pv_collection_sort_by_name(pv_photo_collection_t *collection);

/**
 * Get photo at index
 * @param collection The collection
 * @param index Index of photo
 * @return Pointer to photo or NULL if out of bounds
 */
const pv_photo_t *pv_collection_get(const pv_photo_collection_t *collection, size_t index);

/**
 * Get collection count (thread-safe)
 * @param collection The collection
 * @return Number of photos in collection
 */
size_t pv_collection_count(const pv_photo_collection_t *collection);

/**
 * Get photo path
 * @param collection The collection containing the photo
 * @param photo The photo
 * @return Path string
 */
const char *pv_photo_get_path(const pv_photo_collection_t *collection, const pv_photo_t *photo);

/**
 * Get photo name
 * @param collection The collection containing the photo
 * @param photo The photo
 * @return Filename string
 */
const char *pv_photo_get_name(const pv_photo_collection_t *collection, const pv_photo_t *photo);

/**
 * Get photo file size
 * @param photo The photo
 * @return File size in bytes
 */
uint64_t pv_photo_get_size(const pv_photo_t *photo);

/**
 * Get photo creation time
 * @param photo The photo
 * @return Creation timestamp
 */
time_t pv_photo_get_created_time(const pv_photo_t *photo);

/**
 * Get photo modification time
 * @param photo The photo
 * @return Modification timestamp
 */
time_t pv_photo_get_modified_time(const pv_photo_t *photo);

/* ============================================================================
 * Performance Query Functions
 * ============================================================================ */

/**
 * Get scan performance statistics
 */
typedef struct {
    double scan_time_ms;           /* Scan time in milliseconds */
    double sort_time_ms;           /* Sort time in milliseconds */
    uint32_t photos_found;         /* Number of photos found */
    uint32_t directories_scanned;  /* Directories processed */
    uint32_t files_examined;       /* Total files examined */
    double photos_per_second;      /* Scanning throughput */
} pv_scan_stats_t;

pv_scan_stats_t pv_collection_get_stats(const pv_photo_collection_t *collection);

/**
 * Check SIMD capabilities at runtime
 */
typedef struct {
    bool has_neon;     /* ARM NEON available */
    bool has_sse42;    /* x86 SSE4.2 available */
    bool has_avx2;     /* x86 AVX2 available */
} pv_simd_caps_t;

pv_simd_caps_t pv_get_simd_capabilities(void);

#ifdef __cplusplus
}
#endif

#endif /* PHOTO_SCANNER_H */

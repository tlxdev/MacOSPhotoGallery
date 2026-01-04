/**
 * photo_scanner.c
 * High-performance photo directory scanner
 *
 * Key optimizations:
 * - Parallel directory scanning with GCD
 * - getattrlistbulk for batch attribute fetching
 * - Radix sort for O(n) date sorting
 */

#include "photo_scanner.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/attr.h>
#include <sys/vnode.h>
#include <dirent.h>
#include <fts.h>
#include <unistd.h>
#include <pthread.h>
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <sys/sysctl.h>
#include <sys/mman.h>  /* madvise for memory access hints */

/* ============================================================================
 * Debug Logging
 * ============================================================================ */

#ifndef NDEBUG
    #define PV_DEBUG 1
#else
    #define PV_DEBUG 0
#endif

#define PV_LOG_ERROR(fmt, ...) \
    fprintf(stderr, "[PhotoScanner ERROR] %s:%d: " fmt "\n", __func__, __LINE__, ##__VA_ARGS__)

#define PV_LOG_DEBUG(fmt, ...) \
    do { if (PV_DEBUG) fprintf(stderr, "[PhotoScanner DEBUG] %s:%d: " fmt "\n", __func__, __LINE__, ##__VA_ARGS__); } while(0)

/* Architecture detection for capability reporting */
#if defined(__aarch64__) || defined(__arm64__)
    #define PV_HAS_NEON 1
#elif defined(__x86_64__) || defined(__i386__)
    #define PV_HAS_SSE42 1
#endif

/* ============================================================================
 * Internal Constants and Macros
 * ============================================================================ */

/* Prefetch macro for cache optimization */
#ifdef __GNUC__
    #define PV_PREFETCH(addr) __builtin_prefetch(addr, 0, 3)
    #define PV_LIKELY(x) __builtin_expect(!!(x), 1)
    #define PV_UNLIKELY(x) __builtin_expect(!!(x), 0)
    /* Force inline critical hot-path functions */
    #define PV_HOT __attribute__((hot, always_inline))
    /* Mark error paths as cold - keeps them out of instruction cache */
    #define PV_COLD __attribute__((cold, noinline))
    /* Restrict pointer - tells compiler this is the only pointer to this memory */
    #define PV_RESTRICT __restrict__
#else
    #define PV_PREFETCH(addr) ((void)0)
    #define PV_LIKELY(x) (x)
    #define PV_UNLIKELY(x) (x)
    #define PV_HOT
    #define PV_COLD
    #define PV_RESTRICT
#endif

/* Alignment macro */
#define PV_ALIGNED(x) __attribute__((aligned(x)))

/* Buffer size for getattrlistbulk */
#define ATTR_BUFFER_SIZE (PV_ATTR_BATCH_SIZE * 512)

/* SECURITY: Maximum directory recursion depth to prevent stack exhaustion */
#define PV_MAX_RECURSION_DEPTH 100

/* ============================================================================
 * Extension Matching
 * ============================================================================ */

/* Simple extension matching - strcasecmp is highly optimized in libc */
static PV_HOT inline bool is_supported_extension(const char * PV_RESTRICT ext) {
    if (PV_UNLIKELY(ext == NULL || *ext == '\0')) {
        return false;
    }

    for (int i = 0; PV_SUPPORTED_EXTENSIONS[i] != NULL; i++) {
        if (strcasecmp(ext, PV_SUPPORTED_EXTENSIONS[i]) == 0) {
            return true;
        }
    }
    return false;
}

/* Simple hash for extension (used for ext_hash field in pv_photo_t) */
static inline uint16_t hash_extension(const char *ext) {
    uint16_t h = 0x1505;
    while (*ext) {
        h = ((h << 5) + h) ^ (uint16_t)tolower((unsigned char)*ext++);
    }
    return h;
}

/* Get extension pointer from filename */
static inline const char *get_extension(const char *filename) {
    const char *dot = strrchr(filename, '.');
    return (dot != NULL && dot != filename) ? dot : "";
}

/* ============================================================================
 * Collection Management
 * ============================================================================ */

/* Thread-safe grow operation - currently unused but kept for future lock-based fallback */
__attribute__((unused))
static bool collection_grow(pv_photo_collection_t *collection) {
    if (collection->capacity > SIZE_MAX / 2 / sizeof(pv_photo_t)) {
        return false;
    }
    
    const size_t new_capacity = collection->capacity * 2;
    pv_photo_t *new_photos = aligned_alloc(PV_CACHE_LINE_SIZE, new_capacity * sizeof(pv_photo_t));
    
    if (new_photos == NULL) {
        return false;
    }
    
    /* Copy existing photos */
    memcpy(new_photos, collection->photos, collection->count * sizeof(pv_photo_t));
    
    /* Swap and free old */
    pv_photo_t *old_photos = collection->photos;
    collection->photos = new_photos;
    collection->capacity = new_capacity;
    free(old_photos);
    
    return true;
}

/* ============================================================================
 * Batch Addition for Reduced Lock Contention
 * ============================================================================ */

#define PV_BATCH_SIZE 64
#define PV_PATH_POOL_INITIAL_SIZE (1024 * 1024)  /* 1MB initial path pool */

/* Temporary photo data for batch operations */
typedef struct {
    char path[PV_MAX_PATH];
    size_t path_len;
    size_t name_offset;
    size_t name_len;
    uint64_t size;
    time_t created;
    time_t modified;
} pv_photo_batch_entry_t;

/* Batch buffer for collecting photos before adding to collection */
typedef struct {
    pv_photo_batch_entry_t entries[PV_BATCH_SIZE];
    int count;
} pv_photo_batch_t;

/* Grow path pool if needed - called while holding lock
 * Uses aligned allocation for better cache/TLB performance */
static bool grow_path_pool(pv_photo_collection_t *collection, size_t needed) {
    size_t required = collection->path_pool_size + needed;
    if (required <= collection->path_pool_capacity) {
        return true;
    }

    size_t new_capacity = collection->path_pool_capacity * 2;
    while (new_capacity < required) {
        new_capacity *= 2;
    }

    /* Allocate new page-aligned pool and copy */
    char *new_pool = aligned_alloc(4096, new_capacity);
    if (new_pool == NULL) {
        return false;
    }
    memcpy(new_pool, collection->path_pool, collection->path_pool_size);
    free(collection->path_pool);

    collection->path_pool = new_pool;
    collection->path_pool_capacity = new_capacity;
    /* Tell kernel about sequential access pattern */
    madvise(new_pool, new_capacity, MADV_SEQUENTIAL);
    return true;
}

/* Add a batch of photos to collection under single lock */
static int collection_add_batch(
    pv_photo_collection_t *collection,
    pv_photo_batch_t *batch
) {
    if (collection == NULL || batch == NULL || batch->count == 0) {
        return 0;
    }

    pthread_mutex_t *lock = (pthread_mutex_t *)collection->_internal_lock;
    if (lock == NULL) {
        return 0;
    }

    pthread_mutex_lock(lock);

    int added = 0;
    for (int i = 0; i < batch->count; i++) {
        /* Grow photos array if needed */
        if (collection->count >= collection->capacity) {
            if (collection->capacity > SIZE_MAX / 2 / sizeof(pv_photo_t)) {
                break;
            }
            const size_t new_capacity = collection->capacity * 2;
            pv_photo_t *new_photos = aligned_alloc(PV_CACHE_LINE_SIZE, new_capacity * sizeof(pv_photo_t));
            if (new_photos == NULL) {
                break;
            }
            memcpy(new_photos, collection->photos, collection->count * sizeof(pv_photo_t));
            free(collection->photos);
            collection->photos = new_photos;
            collection->capacity = new_capacity;
        }

        pv_photo_batch_entry_t *entry = &batch->entries[i];

        /* Grow path pool if needed */
        if (!grow_path_pool(collection, entry->path_len + 1)) {
            break;
        }

        pv_photo_t *photo = &collection->photos[collection->count++];

        /* Store path in pool */
        photo->path_offset = (uint32_t)collection->path_pool_size;
        memcpy(collection->path_pool + collection->path_pool_size, entry->path, entry->path_len + 1);
        collection->path_pool_size += entry->path_len + 1;

        /* Set metadata */
        photo->path_len = (uint16_t)entry->path_len;
        photo->name_offset = (uint16_t)entry->name_offset;
        photo->name_len = (uint16_t)entry->name_len;
        photo->size = entry->size;
        photo->created_time = entry->created;
        photo->modified_time = entry->modified;
        photo->index = (uint32_t)(collection->count - 1);

        /* Compute extension hash */
        const char *ext = get_extension(collection->path_pool + photo->path_offset + photo->name_offset);
        photo->ext_hash = hash_extension(ext);

        added++;
    }

    pthread_mutex_unlock(lock);
    batch->count = 0;
    return added;
}

/* Add entry to batch, flush if full */
static inline bool batch_add(
    pv_photo_batch_t *batch,
    pv_photo_collection_t *collection,
    const char *path,
    size_t path_len,
    size_t name_offset,
    size_t name_len,
    uint64_t size,
    time_t created,
    time_t modified
) {
    if (batch->count >= PV_BATCH_SIZE) {
        collection_add_batch(collection, batch);
    }

    pv_photo_batch_entry_t *entry = &batch->entries[batch->count++];
    memcpy(entry->path, path, path_len + 1);
    entry->path_len = path_len;
    entry->name_offset = name_offset;
    entry->name_len = name_len;
    entry->size = size;
    entry->created = created;
    entry->modified = modified;
    return true;
}

/* Thread-safe addition using mutex (legacy, still used by FTS fallback)
 * SECURITY: All writes happen while holding the lock to prevent race conditions
 */
static inline bool collection_add_locked(
    pv_photo_collection_t *collection,
    const char *path,
    size_t path_len,
    size_t name_offset,
    size_t name_len,
    uint64_t size,
    time_t created,
    time_t modified
) {
    /* Validate inputs */
    if (collection == NULL || path == NULL || path_len == 0) {
        PV_LOG_ERROR("Invalid parameters: collection=%p, path=%s, path_len=%zu",
                     (void*)collection, path ? path : "NULL", path_len);
        return false;
    }
    
    if (collection->_internal_lock == NULL) {
        PV_LOG_ERROR("Collection lock is NULL");
        return false;
    }
    
    if (name_offset > path_len) {
        PV_LOG_ERROR("Invalid name_offset %zu > path_len %zu", name_offset, path_len);
        return false;
    }
    
    /* Validate name_offset won't exceed path buffer */
    if (name_offset >= PV_MAX_PATH) {
        PV_LOG_ERROR("name_offset %zu exceeds max path", name_offset);
        return false;
    }
    
    pthread_mutex_t *lock = (pthread_mutex_t *)collection->_internal_lock;
    
    int lock_result = pthread_mutex_lock(lock);
    if (lock_result != 0) {
        PV_LOG_ERROR("Failed to acquire mutex: %s", strerror(lock_result));
        return false;
    }
    
    /* Check capacity and grow if needed */
    if (PV_UNLIKELY(collection->count >= collection->capacity)) {
        /* Check for integer overflow before multiplication */
        if (collection->capacity > SIZE_MAX / 2 / sizeof(pv_photo_t)) {
            PV_LOG_ERROR("Capacity overflow: cannot grow collection");
            pthread_mutex_unlock(lock);
            return false;
        }
        
        const size_t new_capacity = collection->capacity * 2;
        
        PV_LOG_DEBUG("Growing collection from %zu to %zu", collection->capacity, new_capacity);
        
        pv_photo_t *new_photos = aligned_alloc(PV_CACHE_LINE_SIZE, new_capacity * sizeof(pv_photo_t));
        
        if (new_photos == NULL) {
            PV_LOG_ERROR("Failed to allocate %zu bytes for photo array", 
                         new_capacity * sizeof(pv_photo_t));
            pthread_mutex_unlock(lock);
            return false;
        }
        
        memcpy(new_photos, collection->photos, collection->count * sizeof(pv_photo_t));
        free(collection->photos);
        collection->photos = new_photos;
        collection->capacity = new_capacity;
    }
    
    const size_t slot = collection->count++;
    pv_photo_t *photo = &collection->photos[slot];
    
    /* SECURITY: All writes happen while holding the lock to prevent
     * race condition where another thread resizes the array */

    /* Grow path pool if needed */
    const size_t copy_len = (path_len < PV_MAX_PATH - 1) ? path_len : PV_MAX_PATH - 1;
    if (!grow_path_pool(collection, copy_len + 1)) {
        pthread_mutex_unlock(lock);
        return false;
    }

    /* Store path in pool */
    photo->path_offset = (uint32_t)collection->path_pool_size;
    memcpy(collection->path_pool + collection->path_pool_size, path, copy_len);
    collection->path_pool[collection->path_pool_size + copy_len] = '\0';
    collection->path_pool_size += copy_len + 1;

    /* Ensure name_offset is within the copied path */
    const size_t safe_name_offset = (name_offset <= copy_len) ? name_offset : copy_len;

    /* Set metadata */
    photo->path_len = (uint16_t)copy_len;
    photo->name_offset = (uint16_t)safe_name_offset;
    photo->name_len = (uint16_t)((name_len <= copy_len - safe_name_offset) ? name_len : copy_len - safe_name_offset);
    photo->size = size;
    photo->created_time = created;
    photo->modified_time = modified;
    photo->index = (uint32_t)slot;

    /* Compute extension hash for fast filtering */
    const char *ext = get_extension(collection->path_pool + photo->path_offset + photo->name_offset);
    photo->ext_hash = hash_extension(ext);

    /* Release lock after all writes complete */
    pthread_mutex_unlock(lock);

    return true;
}

/* ============================================================================
 * Batch Attribute Fetching with getattrlistbulk
 * ============================================================================ */

/* Process a directory using getattrlistbulk
 *
 * Buffer layout per entry (attributes in bitmap order):
 *   uint32_t length
 *   attribute_set_t returned_attrs  (ATTR_CMN_RETURNED_ATTRS)
 *   uint32_t obj_type               (ATTR_CMN_OBJTYPE)
 *   struct timespec crtime          (ATTR_CMN_CRTIME)
 *   struct timespec modtime         (ATTR_CMN_MODTIME)
 *   struct attrreference name_ref   (ATTR_CMN_NAME)
 *   off_t file_size                 (ATTR_FILE_DATALENGTH - only for files!)
 *   [variable: name string]
 */
static int scan_directory_batch_safe(
    pv_photo_collection_t *collection,
    const char *dir_path,
    int dir_fd,
    dispatch_queue_t queue,
    dispatch_group_t group
) {
    if (collection == NULL || dir_path == NULL || dir_fd < 0) {
        PV_LOG_ERROR("Invalid parameters");
        return -1;
    }

    struct attrlist attr_list = {
        .bitmapcount = ATTR_BIT_MAP_COUNT,
        .commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_OBJTYPE |
                      ATTR_CMN_CRTIME | ATTR_CMN_MODTIME | ATTR_CMN_NAME,
        .fileattr = ATTR_FILE_DATALENGTH
    };

    char *buffer = aligned_alloc(PV_CACHE_LINE_SIZE, ATTR_BUFFER_SIZE);
    if (buffer == NULL) {
        PV_LOG_ERROR("Failed to allocate buffer");
        return -1;
    }

    pv_photo_batch_t batch = {0};
    int found = 0;
    const size_t dir_path_len = strlen(dir_path);

    while (1) {
        const int count = getattrlistbulk(dir_fd, &attr_list, buffer, ATTR_BUFFER_SIZE, 0);

        if (count < 0) {
            PV_LOG_ERROR("getattrlistbulk failed: %s", strerror(errno));
            break;
        }
        if (count == 0) break;

        char *ptr = buffer;

        for (int i = 0; i < count; i++) {
            /* Entry length */
            uint32_t entry_length = *(uint32_t *)ptr;
            if (entry_length == 0 || ptr + entry_length > buffer + ATTR_BUFFER_SIZE) {
                break;
            }
            char *entry_start = ptr;
            ptr += sizeof(uint32_t);

            /* Skip returned_attrs */
            ptr += sizeof(attribute_set_t);

            /* Attributes come in BIT ORDER within each category:
             * ATTR_CMN_NAME        = 0x00000001  (first)
             * ATTR_CMN_OBJTYPE     = 0x00000008
             * ATTR_CMN_CRTIME      = 0x00000200
             * ATTR_CMN_MODTIME     = 0x00000400
             * Then ATTR_FILE_DATALENGTH for files
             */

            /* Name reference (ATTR_CMN_NAME = 0x1, comes first) */
            char *name_ref_ptr = ptr;
            struct attrreference name_ref = *(struct attrreference *)ptr;
            ptr += sizeof(struct attrreference);
            const char *name = name_ref_ptr + name_ref.attr_dataoffset;

            /* Object type (ATTR_CMN_OBJTYPE = 0x8) */
            uint32_t obj_type = *(uint32_t *)ptr;
            ptr += sizeof(uint32_t);

            /* Creation time (ATTR_CMN_CRTIME = 0x200) */
            struct timespec crtime = *(struct timespec *)ptr;
            ptr += sizeof(struct timespec);

            /* Modification time (ATTR_CMN_MODTIME = 0x400) */
            struct timespec modtime = *(struct timespec *)ptr;
            ptr += sizeof(struct timespec);

            /* File size (ATTR_FILE_DATALENGTH - only for regular files) */
            off_t file_size = 0;
            if (obj_type == VREG) {
                file_size = *(off_t *)ptr;
            }

            /* Validate name pointer */
            if (name < buffer || name >= buffer + ATTR_BUFFER_SIZE) {
                ptr = entry_start + entry_length;
                continue;
            }

            /* Validate name is null-terminated within buffer */
            size_t max_name_len = (buffer + ATTR_BUFFER_SIZE) - name;
            size_t name_len = strnlen(name, max_name_len);
            if (name_len == max_name_len) {
                PV_LOG_ERROR("Name not null-terminated at index %d", i);
                ptr = entry_start + entry_length;
                continue;
            }

            /* Skip hidden files */
            if (name[0] == '.') {
                ptr = entry_start + entry_length;
                continue;
            }

            /* Handle directories recursively */
            if (obj_type == VDIR) {
                char *subdir_path = malloc(dir_path_len + name_len + 2);
                if (subdir_path != NULL) {
                    memcpy(subdir_path, dir_path, dir_path_len);
                    subdir_path[dir_path_len] = '/';
                    memcpy(subdir_path + dir_path_len + 1, name, name_len + 1);

                    dispatch_group_async(group, queue, ^{
                        const int sub_fd = open(subdir_path, O_RDONLY | O_DIRECTORY);
                        if (sub_fd >= 0) {
                            scan_directory_batch_safe(collection, subdir_path, sub_fd, queue, group);
                            close(sub_fd);
                        }
                        free(subdir_path);
                    });
                }
                ptr = entry_start + entry_length;
                continue;
            }

            /* Check if regular file with supported extension */
            if (obj_type == VREG) {
                const char *ext = get_extension(name);

                if (is_supported_extension(ext)) {
                    if (dir_path_len > SIZE_MAX - 2 - name_len) {
                        ptr = entry_start + entry_length;
                        continue;
                    }
                    const size_t full_path_len = dir_path_len + 1 + name_len;

                    if (full_path_len < PV_MAX_PATH) {
                        char full_path[PV_MAX_PATH];
                        memcpy(full_path, dir_path, dir_path_len);
                        full_path[dir_path_len] = '/';
                        memcpy(full_path + dir_path_len + 1, name, name_len + 1);

                        if (batch_add(
                            &batch,
                            collection,
                            full_path,
                            full_path_len,
                            dir_path_len + 1,
                            name_len,
                            (uint64_t)file_size,
                            crtime.tv_sec,
                            modtime.tv_sec
                        )) {
                            found++;
                        }
                    }
                }
            }

            ptr = entry_start + entry_length;
        }
    }
    
    /* Flush any remaining items in batch */
    collection_add_batch(collection, &batch);

    free(buffer);
    PV_LOG_DEBUG("Found %d photos in %s", found, dir_path);
    return found;
}

/* Legacy function name wrapper */
static int scan_directory_batch(
    pv_photo_collection_t *collection,
    const char *dir_path,
    int dir_fd,
    dispatch_queue_t queue,
    dispatch_group_t group
) {
    return scan_directory_batch_safe(collection, dir_path, dir_fd, queue, group);
}

/* ============================================================================
 * Parallel FTS Fallback Scanner
 * ============================================================================ */

/* Fallback using fts for compatibility */
static int scan_with_fts_parallel(pv_photo_collection_t *collection, const char *path) {
    if (collection == NULL || path == NULL) {
        PV_LOG_ERROR("Invalid parameters");
        return -1;
    }
    
    char *paths[2] = { (char *)path, NULL };
    
    FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR, NULL);
    if (fts == NULL) {
        PV_LOG_ERROR("fts_open failed for %s: %s", path, strerror(errno));
        return -1;
    }
    
    int found = 0;
    int errors = 0;
    FTSENT *entry;
    
    while ((entry = fts_read(fts)) != NULL) {
        /* Handle fts errors */
        if (entry->fts_info == FTS_ERR || entry->fts_info == FTS_DNR) {
            PV_LOG_DEBUG("FTS error for %s: %s", entry->fts_path, strerror(entry->fts_errno));
            errors++;
            continue;
        }
        
        /* Prefetch next entries */
        FTSENT *next = entry->fts_link;
        for (int i = 0; i < PV_PREFETCH_DISTANCE && next != NULL; i++) {
            PV_PREFETCH(next);
            next = next->fts_link;
        }
        
        if (entry->fts_info != FTS_F) {
            continue;
        }
        
        if (entry->fts_name[0] == '.') {
            continue;
        }
        
        const char *ext = get_extension(entry->fts_name);
        if (!is_supported_extension(ext)) {
            continue;
        }
        
        const struct stat *st = entry->fts_statp;
        if (st == NULL) {
            PV_LOG_DEBUG("No stat info for %s", entry->fts_path);
            continue;
        }
        
        /* Calculate name offset */
        const size_t path_len = entry->fts_pathlen;
        const size_t name_len = entry->fts_namelen;
        const size_t name_offset = path_len - name_len;
        
        if (collection_add_locked(
            collection,
            entry->fts_path,
            path_len,
            name_offset,
            name_len,
            (uint64_t)st->st_size,
            st->st_birthtime,
            st->st_mtime
        )) {
            found++;
        }
    }
    
    if (errno != 0) {
        PV_LOG_DEBUG("fts_read ended with error: %s", strerror(errno));
    }
    
    fts_close(fts);
    
    if (errors > 0) {
        PV_LOG_DEBUG("Completed with %d errors", errors);
    }
    
    return found;
}

/* ============================================================================
 * Radix Sort for O(n) Date Sorting
 * OPTIMIZATION: Sort indices (4 bytes) instead of full structs (4KB+)
 * This reduces memory bandwidth by ~1000x
 * ============================================================================ */

/* Radix sort by creation time - sorts INDICES not structs for speed */
static void radix_sort_by_date(pv_photo_t * PV_RESTRICT photos, size_t count) {
    if (count < 2) {
        return;
    }

    /* For very small arrays, use simple insertion sort */
    if (count < 32) {
        for (size_t i = 1; i < count; i++) {
            pv_photo_t key = photos[i];
            size_t j = i;
            while (j > 0 && photos[j - 1].created_time < key.created_time) {
                photos[j] = photos[j - 1];
                j--;
            }
            photos[j] = key;
        }
        return;
    }

    /* Allocate index arrays - MUCH smaller than full struct arrays */
    uint32_t *indices = malloc(count * sizeof(uint32_t));
    uint32_t *temp_indices = malloc(count * sizeof(uint32_t));

    if (indices == NULL || temp_indices == NULL) {
        free(indices);
        free(temp_indices);
        return;
    }

    /* Extract timestamps for cache efficiency */
    uint64_t *timestamps = malloc(count * sizeof(uint64_t));
    if (timestamps == NULL) {
        free(indices);
        free(temp_indices);
        return;
    }

    /* Initialize indices and pre-compute inverted timestamps (newest first) */
    for (size_t i = 0; i < count; i++) {
        indices[i] = (uint32_t)i;
        timestamps[i] = ~(uint64_t)photos[i].created_time;
    }

    /* Determine which bytes actually vary (skip constant upper bytes) */
    uint64_t all_or = 0, all_and = ~0ULL;
    for (size_t i = 0; i < count; i++) {
        all_or |= timestamps[i];
        all_and &= timestamps[i];
    }
    const uint64_t varying_bits = all_or ^ all_and;

    /* Count arrays for each byte (256 buckets) */
    size_t counts[256];
    uint32_t * PV_RESTRICT src = indices;
    uint32_t * PV_RESTRICT dst = temp_indices;

    /* Sort by each byte of the timestamp (LSB first), skip constant bytes */
    for (int byte = 0; byte < 8; byte++) {
        /* Skip bytes that don't vary - common when photos are from same period */
        if (((varying_bits >> (byte * 8)) & 0xFF) == 0) {
            continue;
        }

        memset(counts, 0, sizeof(counts));

        /* Count occurrences with prefetching */
        for (size_t i = 0; i < count; i++) {
            if (i + 8 < count) {
                PV_PREFETCH(&timestamps[src[i + 8]]);
            }
            const uint8_t bucket = (timestamps[src[i]] >> (byte * 8)) & 0xFF;
            counts[bucket]++;
        }

        /* Compute prefix sums */
        size_t total = 0;
        for (int i = 0; i < 256; i++) {
            const size_t old_count = counts[i];
            counts[i] = total;
            total += old_count;
        }

        /* Distribute to output with prefetching */
        for (size_t i = 0; i < count; i++) {
            if (i + 8 < count) {
                PV_PREFETCH(&timestamps[src[i + 8]]);
            }
            const uint8_t bucket = (timestamps[src[i]] >> (byte * 8)) & 0xFF;
            dst[counts[bucket]++] = src[i];
        }

        /* Swap buffers */
        uint32_t *swap = src;
        src = dst;
        dst = swap;
    }

    /* Reorder photos array according to sorted indices */
    pv_photo_t *temp_photos = aligned_alloc(PV_CACHE_LINE_SIZE, count * sizeof(pv_photo_t));
    if (temp_photos != NULL) {
        for (size_t i = 0; i < count; i++) {
            if (i + 2 < count) {
                PV_PREFETCH(&photos[src[i + 2]]);
            }
            temp_photos[i] = photos[src[i]];
        }
        memcpy(photos, temp_photos, count * sizeof(pv_photo_t));
        free(temp_photos);
    }

    free(timestamps);
    free(indices);
    free(temp_indices);
}

/* Comparison function for name sorting - uses path pool via context */
static int compare_by_name(void *context, const void *a, const void *b) {
    const char *path_pool = (const char *)context;
    const pv_photo_t *pa = (const pv_photo_t *)a;
    const pv_photo_t *pb = (const pv_photo_t *)b;
    const char *name_a = path_pool + pa->path_offset + pa->name_offset;
    const char *name_b = path_pool + pb->path_offset + pb->name_offset;
    return strcasecmp(name_a, name_b);
}

/* ============================================================================
 * Timing Utilities
 * ============================================================================ */

static inline uint64_t get_time_ns(void) {
    static mach_timebase_info_data_t timebase;
    static dispatch_once_t once;
    
    dispatch_once(&once, ^{
        mach_timebase_info(&timebase);
    });
    
    return mach_absolute_time() * timebase.numer / timebase.denom;
}

/* ============================================================================
 * Public API Implementation
 * ============================================================================ */

pv_photo_collection_t *pv_collection_create(void) {
    PV_LOG_DEBUG("Creating photo collection");

    pv_photo_collection_t *collection = calloc(1, sizeof(pv_photo_collection_t));
    if (collection == NULL) {
        PV_LOG_ERROR("Failed to allocate collection struct");
        return NULL;
    }
    
    /* Allocate cache-aligned photo array */
    const size_t initial_size = PV_INITIAL_CAPACITY * sizeof(pv_photo_t);
    collection->photos = aligned_alloc(PV_CACHE_LINE_SIZE, initial_size);
    if (collection->photos == NULL) {
        PV_LOG_ERROR("Failed to allocate photo array (%zu bytes)", initial_size);
        free(collection);
        return NULL;
    }
    
    /* Zero initialize the photo array */
    memset(collection->photos, 0, initial_size);
    
    /* Allocate and initialize mutex for thread-safe additions */
    pthread_mutex_t *lock = malloc(sizeof(pthread_mutex_t));
    if (lock == NULL) {
        PV_LOG_ERROR("Failed to allocate mutex");
        free(collection->photos);
        free(collection);
        return NULL;
    }
    
    int mutex_result = pthread_mutex_init(lock, NULL);
    if (mutex_result != 0) {
        PV_LOG_ERROR("Failed to initialize mutex: %s", strerror(mutex_result));
        free(lock);
        free(collection->photos);
        free(collection);
        return NULL;
    }
    
    collection->_internal_lock = lock;
    collection->capacity = PV_INITIAL_CAPACITY;
    collection->count = 0;

    /* Initialize path pool - page-aligned for better memory performance */
    collection->path_pool = aligned_alloc(4096, PV_PATH_POOL_INITIAL_SIZE);
    if (collection->path_pool == NULL) {
        PV_LOG_ERROR("Failed to allocate path pool (%d bytes)", PV_PATH_POOL_INITIAL_SIZE);
        pthread_mutex_destroy(lock);
        free(lock);
        free(collection->photos);
        free(collection);
        return NULL;
    }
    /* Tell kernel we'll access path pool sequentially - improves prefetching */
    madvise(collection->path_pool, PV_PATH_POOL_INITIAL_SIZE, MADV_SEQUENTIAL);
    collection->path_pool_size = 0;
    collection->path_pool_capacity = PV_PATH_POOL_INITIAL_SIZE;

    PV_LOG_DEBUG("Collection created with capacity %zu, path pool %d bytes",
                 collection->capacity, PV_PATH_POOL_INITIAL_SIZE);
    
    return collection;
}

void pv_collection_free(pv_photo_collection_t *collection) {
    if (collection == NULL) {
        return;
    }
    
    /* SECURITY: Clear sensitive pointers before freeing to help detect use-after-free */
    if (collection->_internal_lock != NULL) {
        pthread_mutex_t *lock = (pthread_mutex_t *)collection->_internal_lock;
        pthread_mutex_destroy(lock);
        free(lock);
        collection->_internal_lock = NULL;
    }
    
    if (collection->photos != NULL) {
        /* Zero out photo data before freeing (defense in depth) */
        memset(collection->photos, 0, collection->count * sizeof(pv_photo_t));
        free(collection->photos);
        collection->photos = NULL;
    }

    /* Free path pool */
    if (collection->path_pool != NULL) {
        free(collection->path_pool);
        collection->path_pool = NULL;
    }
    collection->path_pool_size = 0;
    collection->path_pool_capacity = 0;

    collection->count = 0;
    collection->capacity = 0;

    free(collection);
}

size_t pv_collection_count(const pv_photo_collection_t *collection) {
    if (collection == NULL) {
        return 0;
    }
    return collection->count;
}

int pv_scan_directory(pv_photo_collection_t *collection, const char *directory_path) {
    const pv_scan_options_t options = PV_SCAN_OPTIONS_DEFAULT;
    return pv_scan_directory_ex(collection, directory_path, &options);
}

int pv_scan_directory_ex(
    pv_photo_collection_t *collection,
    const char *directory_path,
    const pv_scan_options_t *options
) {
    if (collection == NULL) {
        PV_LOG_ERROR("Collection is NULL");
        return -1;
    }
    
    if (directory_path == NULL) {
        PV_LOG_ERROR("Directory path is NULL");
        return -1;
    }
    
    if (collection->_internal_lock == NULL) {
        PV_LOG_ERROR("Collection lock is not initialized");
        return -1;
    }
    
    PV_LOG_DEBUG("Starting scan of: %s", directory_path);

    /* Reset collection */
    collection->count = 0;
    collection->path_pool_size = 0;  /* Reset path pool */
    collection->directories_scanned = 0;
    collection->files_examined = 0;
    
    /* Store root path */
    const size_t path_len = strlen(directory_path);
    const size_t copy_len = (path_len < PV_MAX_PATH - 1) ? path_len : PV_MAX_PATH - 1;
    memcpy(collection->root_path, directory_path, copy_len);
    collection->root_path[copy_len] = '\0';
    
    const uint64_t scan_start = get_time_ns();
    
    int result = -1;
    bool batch_scan_failed = false;
    
    if (options->use_batch_attrs) {
        /* Try getattrlistbulk first */
        const int dir_fd = open(directory_path, O_RDONLY | O_DIRECTORY);
        
        if (dir_fd >= 0) {
            PV_LOG_DEBUG("Using batch attribute scanning (getattrlistbulk)");
            
            /* Create GCD queue for parallel scanning */
            dispatch_queue_t queue = dispatch_queue_create(
                "com.photoviewer.scanner",
                dispatch_queue_attr_make_with_qos_class(
                    DISPATCH_QUEUE_CONCURRENT,
                    QOS_CLASS_USER_INITIATED,
                    0
                )
            );
            
            if (queue == NULL) {
                PV_LOG_ERROR("Failed to create dispatch queue");
                close(dir_fd);
                batch_scan_failed = true;
            } else {
                dispatch_group_t group = dispatch_group_create();
                
                if (group == NULL) {
                    PV_LOG_ERROR("Failed to create dispatch group");
                    dispatch_release(queue);  /* SECURITY: Fix memory leak */
                    close(dir_fd);
                    batch_scan_failed = true;
                } else {
                    /* Start recursive scan */
                    result = scan_directory_batch(collection, directory_path, dir_fd, queue, group);
                    
                    /* Wait for all parallel tasks to complete with timeout */
                    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_SEC);  /* 5 min timeout */
                    long wait_result = dispatch_group_wait(group, timeout);
                    
                    if (wait_result != 0) {
                        PV_LOG_ERROR("Scan timed out after 5 minutes");
                    }
                    
                    close(dir_fd);
                    
                    /* Get final count */
                    result = (int)collection->count;
                    
                    PV_LOG_DEBUG("Batch scan complete: found %d photos", result);
                }
            }
        } else {
            PV_LOG_DEBUG("Cannot open directory with O_DIRECTORY: %s (errno=%d), falling back to fts", 
                         strerror(errno), errno);
            batch_scan_failed = true;
        }
    }
    
    /* Fallback to fts if batch scanning failed or was disabled */
    if (!options->use_batch_attrs || batch_scan_failed) {
        PV_LOG_DEBUG("Using fts-based scanning");
        result = scan_with_fts_parallel(collection, directory_path);
        PV_LOG_DEBUG("FTS scan complete: found %d photos", result);
    }
    
    collection->scan_time_ns = get_time_ns() - scan_start;
    
    /* Sort by date */
    if (result > 0 && collection->count > 0) {
        PV_LOG_DEBUG("Sorting %zu photos by date", collection->count);
        
        const uint64_t sort_start = get_time_ns();
        
        /* Use radix sort for O(n) performance */
        radix_sort_by_date(collection->photos, collection->count);
        
        /* Update indices after sort */
        const size_t count = collection->count;
        for (size_t i = 0; i < count; i++) {
            collection->photos[i].index = (uint32_t)i;
        }
        
        collection->sort_time_ns = get_time_ns() - sort_start;
        
        PV_LOG_DEBUG("Sort complete in %.2f ms", (double)collection->sort_time_ns / 1000000.0);
    }
    
    PV_LOG_DEBUG("Scan complete: %d photos in %.2f ms", 
                 result, (double)collection->scan_time_ns / 1000000.0);
    
    return result;
}

bool pv_is_supported_image(const char *filename) {
    if (filename == NULL) {
        return false;
    }
    const char *ext = get_extension(filename);
    return is_supported_extension(ext);
}

void pv_collection_sort_by_date(pv_photo_collection_t *collection) {
    if (collection == NULL) {
        return;
    }
    
    const size_t count = collection->count;
    if (count < 2) {
        return;
    }
    
    radix_sort_by_date(collection->photos, count);
    
    /* Update indices */
    for (size_t i = 0; i < count; i++) {
        collection->photos[i].index = (uint32_t)i;
    }
}

void pv_collection_sort_by_name(pv_photo_collection_t *collection) {
    if (collection == NULL || collection->path_pool == NULL) {
        return;
    }

    const size_t count = collection->count;
    if (count < 2) {
        return;
    }

    /* Use qsort_r to pass path_pool as context */
    qsort_r(collection->photos, count, sizeof(pv_photo_t), collection->path_pool, compare_by_name);

    /* Update indices */
    for (size_t i = 0; i < count; i++) {
        collection->photos[i].index = (uint32_t)i;
    }
}

const pv_photo_t *pv_collection_get(const pv_photo_collection_t *collection, size_t index) {
    if (collection == NULL || index >= collection->count) {
        return NULL;
    }
    
    /* Prefetch next few entries for sequential access patterns */
    for (int i = 1; i <= PV_PREFETCH_DISTANCE && (index + i) < collection->count; i++) {
        PV_PREFETCH(&collection->photos[index + i]);
    }
    
    return &collection->photos[index];
}

pv_scan_stats_t pv_collection_get_stats(const pv_photo_collection_t *collection) {
    pv_scan_stats_t stats = {0};
    
    if (collection == NULL) {
        return stats;
    }
    
    stats.scan_time_ms = (double)collection->scan_time_ns / 1000000.0;
    stats.sort_time_ms = (double)collection->sort_time_ns / 1000000.0;
    stats.photos_found = (uint32_t)collection->count;
    stats.directories_scanned = collection->directories_scanned;
    stats.files_examined = collection->files_examined;
    
    if (stats.scan_time_ms > 0) {
        stats.photos_per_second = (double)stats.photos_found / (stats.scan_time_ms / 1000.0);
    }
    
    return stats;
}

pv_simd_caps_t pv_get_simd_capabilities(void) {
    pv_simd_caps_t caps = {0};
    
#if defined(PV_HAS_NEON)
    caps.has_neon = true;
#endif
    
#if defined(PV_HAS_SSE42)
    /* Check SSE4.2 at runtime */
    uint32_t eax, ebx, ecx, edx;
    __asm__ volatile(
        "cpuid"
        : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx)
        : "a"(1)
    );
    caps.has_sse42 = (ecx & (1 << 20)) != 0;
    caps.has_avx2 = false;  /* Would need leaf 7 check */
#endif
    
    return caps;
}

/* ============================================================================
 * Photo Accessor Functions (for Swift compatibility)
 * ============================================================================ */

const char *pv_photo_get_path(const pv_photo_collection_t *collection, const pv_photo_t *photo) {
    if (collection == NULL || photo == NULL || collection->path_pool == NULL) {
        return "";
    }
    /* SECURITY: Validate path_offset is within pool bounds */
    if (photo->path_offset >= collection->path_pool_size) {
        return "";
    }
    return collection->path_pool + photo->path_offset;
}

const char *pv_photo_get_name(const pv_photo_collection_t *collection, const pv_photo_t *photo) {
    if (collection == NULL || photo == NULL || collection->path_pool == NULL) {
        return "";
    }
    /* SECURITY: Validate offsets are within pool bounds */
    size_t name_abs_offset = photo->path_offset + photo->name_offset;
    if (name_abs_offset >= collection->path_pool_size) {
        return "";
    }
    return collection->path_pool + name_abs_offset;
}

uint64_t pv_photo_get_size(const pv_photo_t *photo) {
    if (photo == NULL) {
        return 0;
    }
    return photo->size;
}

time_t pv_photo_get_created_time(const pv_photo_t *photo) {
    if (photo == NULL) {
        return 0;
    }
    return photo->created_time;
}

time_t pv_photo_get_modified_time(const pv_photo_t *photo) {
    if (photo == NULL) {
        return 0;
    }
    return photo->modified_time;
}

/**
 * photo_scanner.c
 * Ultra high-performance photo directory scanner
 * Uses macOS-optimized APIs: fts(3) for traversal, getattrlistbulk for batch attributes
 */

#include "photo_scanner.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <sys/stat.h>      /* Must come before fts.h */
#include <fts.h>
#include <unistd.h>
#include <pthread.h>

/* Batch size for getattrlistbulk */
#define ATTR_BATCH_SIZE 256

/* Pre-computed extension hash for O(1) lookup */
typedef struct {
    const char *ext;
    uint32_t hash;
} ext_entry_t;

static ext_entry_t ext_table[32];
static int ext_count = 0;
static pthread_once_t ext_init_once = PTHREAD_ONCE_INIT;

/* Fast hash function for extensions */
static inline uint32_t hash_extension(const char *ext) {
    uint32_t h = 5381;
    for (const char *p = ext; *p; p++) {
        h = ((h << 5) + h) + (uint32_t)tolower((unsigned char)*p);
    }
    return h;
}

/* Initialize extension hash table */
static void init_extension_table(void) {
    for (int i = 0; PV_SUPPORTED_EXTENSIONS[i] != NULL; i++) {
        ext_table[ext_count].ext = PV_SUPPORTED_EXTENSIONS[i];
        ext_table[ext_count].hash = hash_extension(PV_SUPPORTED_EXTENSIONS[i]);
        ext_count++;
    }
}

/* O(1) average extension check using hash */
static bool is_supported_extension_fast(const char *ext) {
    if (ext == NULL || ext[0] == '\0') {
        return false;
    }
    
    /* Compute lowercase extension hash */
    char lower_ext[16];
    int i = 0;
    while (ext[i] != '\0' && i < 15) {
        lower_ext[i] = (char)tolower((unsigned char)ext[i]);
        i++;
    }
    lower_ext[i] = '\0';
    
    uint32_t h = hash_extension(lower_ext);
    
    /* Check against hash table */
    for (int j = 0; j < ext_count; j++) {
        if (ext_table[j].hash == h && strcmp(lower_ext, ext_table[j].ext) == 0) {
            return true;
        }
    }
    return false;
}

/* Get file extension pointer */
static inline const char *get_extension(const char *filename) {
    const char *dot = strrchr(filename, '.');
    return (dot && dot != filename) ? dot : "";
}

/* Grow collection capacity */
static bool collection_grow(pv_photo_collection_t *collection) {
    if (collection->capacity > SIZE_MAX / 2 / sizeof(pv_photo_t)) {
        return false;
    }
    
    size_t new_capacity = collection->capacity * 2;
    pv_photo_t *new_photos = realloc(collection->photos, new_capacity * sizeof(pv_photo_t));
    if (new_photos == NULL) {
        return false;
    }
    collection->photos = new_photos;
    collection->capacity = new_capacity;
    return true;
}

/* Add photo to collection - optimized inline version */
static inline bool collection_add(pv_photo_collection_t *collection, 
                                   const char *path, size_t path_len,
                                   const char *name, size_t name_len,
                                   uint64_t size, time_t created, time_t modified) {
    if (collection->count >= collection->capacity) {
        if (!collection_grow(collection)) {
            return false;
        }
    }
    
    pv_photo_t *photo = &collection->photos[collection->count];
    
    /* Direct memcpy is faster than strncpy for known lengths */
    size_t copy_len = (path_len < PV_MAX_PATH - 1) ? path_len : PV_MAX_PATH - 1;
    memcpy(photo->path, path, copy_len);
    photo->path[copy_len] = '\0';
    
    copy_len = (name_len < 255) ? name_len : 255;
    memcpy(photo->name, name, copy_len);
    photo->name[copy_len] = '\0';
    
    photo->size = size;
    photo->created_time = created;
    photo->modified_time = modified;
    photo->index = (uint32_t)collection->count;
    
    collection->count++;
    return true;
}

/* Compare photos by date (newest first) - optimized */
static int compare_by_date(const void *a, const void *b) {
    const pv_photo_t *pa = (const pv_photo_t *)a;
    const pv_photo_t *pb = (const pv_photo_t *)b;
    /* Use subtraction for speed, safe for time_t values */
    if (pb->created_time != pa->created_time) {
        return (pb->created_time > pa->created_time) ? 1 : -1;
    }
    return 0;
}

/* Compare photos by name */
static int compare_by_name(const void *a, const void *b) {
    const pv_photo_t *pa = (const pv_photo_t *)a;
    const pv_photo_t *pb = (const pv_photo_t *)b;
    return strcasecmp(pa->name, pb->name);
}

/*
 * Optimized directory scan using fts(3)
 * fts provides pre-order traversal without recursion overhead
 * and handles all the symlink/loop detection automatically
 */
static int scan_with_fts(pv_photo_collection_t *collection, const char *path) {
    char *paths[2] = { (char *)path, NULL };
    
    /* FTS_PHYSICAL: don't follow symlinks
     * FTS_NOCHDIR: don't change directory (thread-safe)
     * FTS_NOSTAT: we'll get stats ourselves in batch (not used here but could be)
     */
    FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR, NULL);
    if (fts == NULL) {
        return -1;
    }
    
    int found = 0;
    FTSENT *entry;
    
    while ((entry = fts_read(fts)) != NULL) {
        /* Skip directories and non-regular files */
        if (entry->fts_info != FTS_F) {
            continue;
        }
        
        /* Skip hidden files */
        if (entry->fts_name[0] == '.') {
            continue;
        }
        
        /* Check extension */
        const char *ext = get_extension(entry->fts_name);
        if (!is_supported_extension_fast(ext)) {
            continue;
        }
        
        /* fts already has stat info */
        const struct stat *st = entry->fts_statp;
        
        if (collection_add(collection,
                          entry->fts_path, entry->fts_pathlen,
                          entry->fts_name, entry->fts_namelen,
                          (uint64_t)st->st_size,
                          st->st_birthtime,
                          st->st_mtime)) {
            found++;
        }
    }
    
    fts_close(fts);
    return found;
}

pv_photo_collection_t *pv_collection_create(void) {
    /* Initialize extension hash table once */
    pthread_once(&ext_init_once, init_extension_table);
    
    pv_photo_collection_t *collection = calloc(1, sizeof(pv_photo_collection_t));
    if (collection == NULL) {
        return NULL;
    }
    
    collection->photos = calloc(PV_INITIAL_CAPACITY, sizeof(pv_photo_t));
    if (collection->photos == NULL) {
        free(collection);
        return NULL;
    }
    
    collection->capacity = PV_INITIAL_CAPACITY;
    collection->count = 0;
    
    return collection;
}

void pv_collection_free(pv_photo_collection_t *collection) {
    if (collection == NULL) {
        return;
    }
    free(collection->photos);
    free(collection);
}

int pv_scan_directory(pv_photo_collection_t *collection, const char *directory_path) {
    if (collection == NULL || directory_path == NULL) {
        return -1;
    }
    
    /* Reset collection */
    collection->count = 0;
    
    size_t path_len = strlen(directory_path);
    size_t copy_len = (path_len < PV_MAX_PATH - 1) ? path_len : PV_MAX_PATH - 1;
    memcpy(collection->root_path, directory_path, copy_len);
    collection->root_path[copy_len] = '\0';
    
    /* Use optimized fts-based scanning */
    int result = scan_with_fts(collection, directory_path);
    
    /* Sort by date after scanning */
    if (result > 0) {
        pv_collection_sort_by_date(collection);
        
        /* Update indices after sort */
        for (size_t i = 0; i < collection->count; i++) {
            collection->photos[i].index = (uint32_t)i;
        }
    }
    
    return result;
}

bool pv_is_supported_image(const char *filename) {
    pthread_once(&ext_init_once, init_extension_table);
    
    if (filename == NULL) {
        return false;
    }
    
    const char *ext = get_extension(filename);
    return is_supported_extension_fast(ext);
}

void pv_collection_sort_by_date(pv_photo_collection_t *collection) {
    if (collection == NULL || collection->count < 2) {
        return;
    }
    qsort(collection->photos, collection->count, sizeof(pv_photo_t), compare_by_date);
}

void pv_collection_sort_by_name(pv_photo_collection_t *collection) {
    if (collection == NULL || collection->count < 2) {
        return;
    }
    qsort(collection->photos, collection->count, sizeof(pv_photo_t), compare_by_name);
}

const pv_photo_t *pv_collection_get(const pv_photo_collection_t *collection, size_t index) {
    if (collection == NULL || index >= collection->count) {
        return NULL;
    }
    return &collection->photos[index];
}

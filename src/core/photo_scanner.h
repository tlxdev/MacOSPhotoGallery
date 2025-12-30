/**
 * photo_scanner.h
 * Core C library for high-performance photo directory scanning
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

/* Maximum path length */
#define PV_MAX_PATH 4096

/* Maximum supported photos (can be reallocated) */
#define PV_INITIAL_CAPACITY 10000

/* Photo file information */
typedef struct {
    char path[PV_MAX_PATH];
    char name[256];
    uint64_t size;
    time_t created_time;
    time_t modified_time;
    uint32_t index;
} pv_photo_t;

/* Photo collection */
typedef struct {
    pv_photo_t *photos;
    size_t count;
    size_t capacity;
    char root_path[PV_MAX_PATH];
} pv_photo_collection_t;

/* Supported image extensions */
static const char *PV_SUPPORTED_EXTENSIONS[] = {
    ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp",
    ".tiff", ".tif", ".heic", ".heif", ".avif",
    ".raw", ".cr2", ".nef", ".arw", ".dng",
    NULL
};

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
 * Scan a directory recursively for photos
 * @param collection The collection to populate
 * @param directory_path Path to scan
 * @return Number of photos found, or -1 on error
 */
int pv_scan_directory(pv_photo_collection_t *collection, const char *directory_path);

/**
 * Check if a file extension is a supported image format
 * @param filename The filename to check
 * @return true if supported, false otherwise
 */
bool pv_is_supported_image(const char *filename);

/**
 * Sort collection by creation time (newest first)
 * @param collection The collection to sort
 */
void pv_collection_sort_by_date(pv_photo_collection_t *collection);

/**
 * Sort collection by name (alphabetical)
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

#ifdef __cplusplus
}
#endif

#endif /* PHOTO_SCANNER_H */


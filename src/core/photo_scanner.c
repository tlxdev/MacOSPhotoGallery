/**
 * photo_scanner.c
 * High-performance photo directory scanner
 */

#include "photo_scanner.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <ctype.h>

/* Internal: Convert string to lowercase for comparison */
static void str_to_lower(char *dest, const char *src, size_t max_len) {
    size_t i = 0;
    while (src[i] != '\0' && i < max_len - 1) {
        dest[i] = (char)tolower((unsigned char)src[i]);
        i++;
    }
    dest[i] = '\0';
}

/* Internal: Get file extension */
static const char *get_extension(const char *filename) {
    const char *dot = strrchr(filename, '.');
    if (dot == NULL || dot == filename) {
        return "";
    }
    return dot;
}

/* Internal: Grow collection capacity */
static bool collection_grow(pv_photo_collection_t *collection) {
    size_t new_capacity = collection->capacity * 2;
    pv_photo_t *new_photos = realloc(collection->photos, new_capacity * sizeof(pv_photo_t));
    if (new_photos == NULL) {
        return false;
    }
    collection->photos = new_photos;
    collection->capacity = new_capacity;
    return true;
}

/* Internal: Add photo to collection */
static bool collection_add(pv_photo_collection_t *collection, const pv_photo_t *photo) {
    if (collection->count >= collection->capacity) {
        if (!collection_grow(collection)) {
            return false;
        }
    }
    collection->photos[collection->count] = *photo;
    collection->photos[collection->count].index = (uint32_t)collection->count;
    collection->count++;
    return true;
}

/* Internal: Compare photos by date (newest first) */
static int compare_by_date(const void *a, const void *b) {
    const pv_photo_t *pa = (const pv_photo_t *)a;
    const pv_photo_t *pb = (const pv_photo_t *)b;
    if (pb->created_time > pa->created_time) {
        return 1;
    }
    if (pb->created_time < pa->created_time) {
        return -1;
    }
    return 0;
}

/* Internal: Compare photos by name */
static int compare_by_name(const void *a, const void *b) {
    const pv_photo_t *pa = (const pv_photo_t *)a;
    const pv_photo_t *pb = (const pv_photo_t *)b;
    return strcasecmp(pa->name, pb->name);
}

/* Internal: Recursive directory scan */
static int scan_recursive(pv_photo_collection_t *collection, const char *path) {
    DIR *dir = opendir(path);
    if (dir == NULL) {
        return -1;
    }
    
    int found = 0;
    struct dirent *entry;
    
    while ((entry = readdir(dir)) != NULL) {
        /* Skip hidden files and . / .. */
        if (entry->d_name[0] == '.') {
            continue;
        }
        
        char full_path[PV_MAX_PATH];
        int len = snprintf(full_path, sizeof(full_path), "%s/%s", path, entry->d_name);
        if (len < 0 || (size_t)len >= sizeof(full_path)) {
            continue;
        }
        
        struct stat st;
        if (stat(full_path, &st) != 0) {
            continue;
        }
        
        if (S_ISDIR(st.st_mode)) {
            /* Recurse into subdirectory */
            int sub_found = scan_recursive(collection, full_path);
            if (sub_found > 0) {
                found += sub_found;
            }
        } else if (S_ISREG(st.st_mode) && pv_is_supported_image(entry->d_name)) {
            /* Add image file */
            pv_photo_t photo = {0};
            strncpy(photo.path, full_path, sizeof(photo.path) - 1);
            strncpy(photo.name, entry->d_name, sizeof(photo.name) - 1);
            photo.size = (uint64_t)st.st_size;
            photo.created_time = st.st_birthtime;
            photo.modified_time = st.st_mtime;
            
            if (collection_add(collection, &photo)) {
                found++;
            }
        }
    }
    
    closedir(dir);
    return found;
}

pv_photo_collection_t *pv_collection_create(void) {
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
    strncpy(collection->root_path, directory_path, sizeof(collection->root_path) - 1);
    
    int result = scan_recursive(collection, directory_path);
    
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
    if (filename == NULL) {
        return false;
    }
    
    const char *ext = get_extension(filename);
    if (ext[0] == '\0') {
        return false;
    }
    
    char lower_ext[16];
    str_to_lower(lower_ext, ext, sizeof(lower_ext));
    
    for (int i = 0; PV_SUPPORTED_EXTENSIONS[i] != NULL; i++) {
        if (strcmp(lower_ext, PV_SUPPORTED_EXTENSIONS[i]) == 0) {
            return true;
        }
    }
    
    return false;
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


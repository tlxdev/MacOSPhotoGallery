# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PhotoViewer is a native macOS image viewer built with Swift/SwiftUI frontend and a high-performance C backend for directory scanning. It targets macOS 14.0+ (arm64).

## Build Commands

```bash
make              # Build release app bundle
make debug        # Build with debug symbols
make release      # Maximum performance build
make run          # Build and launch
make test         # Run unit tests
make clean        # Remove build artifacts
make sign-adhoc   # Ad-hoc sign for local testing
make dmg          # Create distribution DMG
```

## Architecture

### Hybrid Swift/C Design

The app uses a two-layer architecture:

1. **C Core** (`src/core/photo_scanner.c`) - High-performance directory scanner with:
   - SIMD-accelerated extension matching (ARM NEON / x86 SSE4.2)
   - Cache-aligned structures (64-byte alignment)
   - Parallel scanning via GCD
   - `getattrlistbulk` for batch attribute fetching
   - Radix sort for O(n) date sorting

2. **Swift UI** (`src/swift/`) - SwiftUI application layer with:
   - `PhotoStore.swift` as central state manager (`@Observable`)
   - Bridge to C scanner via `PhotoViewer-Bridging-Header.h`
   - Actor-based `LRUCache` for thread-safe caching

### Key Files

- `src/core/photo_scanner.h` - C API: `pv_scan_directory()`, `pv_collection_*`, `pv_photo_t`
- `src/swift/Models/PhotoStore.swift` - Central state, bridges Swift to C
- `src/swift/Core/LRUCache.swift` - O(1) thread-safe cache implementation

### Supported Image Formats

JPG, JPEG, PNG, GIF, BMP, TIFF, TIF, WEBP, HEIC, HEIF, AVIF, RAW, CR2, CR3, NEF, ARW, DNG

## Testing

Tests use a custom Swift framework in `tests/`:
```bash
make test
```

Test files: `LRUCacheTests.swift`, `DateFormattersTests.swift`, `PhotoItemTests.swift`

## Build Configuration

- **C Compiler**: clang with `-O3 -march=native -flto -ffast-math`
- **Swift Compiler**: swiftc with `-O -whole-module-optimization`
- **Warnings**: `-Wall -Wextra -Werror` (warnings are errors)
- **Output**: `build/PhotoViewer.app`

## App Bundle

- Bundle ID: `com.photoviewer.app`
- Entitlements: App sandbox with user-selected file access, Photos/Downloads read access
- Resources in `resources/` (icons)

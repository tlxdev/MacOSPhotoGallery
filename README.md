# PhotoViewer

MacOS native image viewer, because Apple's default image viewer sucks.

Made in Finland in 2025

## Tech Stack

- **Swift** + **SwiftUI** for the UI
- **C** for high-performance directory scanning
- **Liquid Glass** design (iOS 26 / macOS 26 style)

External dependencies: None

## Requirements

Xcode Command Line Tools (includes Swift and Clang)

## Building

```bash
make
```

## Running

```bash
make run
```

## Features

- High-performance photo browsing with C-based directory scanning
- Beautiful Liquid Glass UI with translucent materials
- Adaptive grid view for browsing large photo collections
- Metadata panel showing EXIF information
- Keyboard shortcuts for fast navigation
- Recent folders for quick access

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Arrow keys | Navigate photos |
| G | Toggle grid view |
| I | Toggle info panel |
| Cmd+O | Open folder |
| Cmd+C | Copy current photo |

## Project Structure

```
src/
  core/           # C scanner for fast directory traversal
    photo_scanner.c
    photo_scanner.h
  swift/          # Swift/SwiftUI application
    PhotoViewerApp.swift
    Models/
      PhotoItem.swift
      PhotoStore.swift
    Views/
      ContentView.swift
      WelcomeView.swift
      ToolbarView.swift
      PhotoDisplayView.swift
      PhotoGridView.swift
      MetadataPanel.swift
      ThumbnailCache.swift
```

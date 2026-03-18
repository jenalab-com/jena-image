<p align="center">
  <img src="jena_image_icon_1024.jpg" alt="JenaImage" width="200">
</p>

<h1 align="center">JenaImage</h1>

<p align="center">
  macOS native image viewer built with Swift and AppKit
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014.0+-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9+-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

---

## Features

- **Folder Sidebar** — Register folders and browse the folder tree with hierarchical navigation; media count shown per folder
- **Grid Browser** — View images and folders as a thumbnail grid with adjustable size; video files show a play badge
- **Image Viewer** — In-panel viewer with zoom, flip (horizontal/vertical), and thumbnail strip navigation; sidebar syncs to current file
- **Video Player** — Play MP4, MOV, M4V, AVI, MKV files inline with AVKit
- **Format Conversion** — Export images to JPEG, PNG, WebP, HEIC, HEIF, AVIF, TIFF, BMP, GIF
- **File Management** — Rename, move, copy, delete files with drag-and-drop support; sidebar context menu with Reveal in Finder, Rename, Export, Delete
- **Keyboard Shortcuts** — Full keyboard support for all major operations

## Screenshots

> Coming soon

## Requirements

- macOS 14.0 (Sonoma) or later

## Build

This project uses a Makefile-based build system — no Xcode project required.

```bash
# Clone
git clone https://github.com/jenalab/jena-image.git
cd jena-image

# Build
make build

# Build and run
make run

# Install to ~/Applications
make install

# Create .pkg installer
make pkg

# Clean build artifacts
make clean
```

## Architecture

Feature-first directory structure with inward dependency flow (UI → Service → Model).

```
Sources/
├── app/          # AppDelegate, MainWindowController, Menus, Toolbar
├── sidebar/      # Folder tree navigation (NSOutlineView)
├── browser/      # Image/folder grid (NSCollectionView)
├── viewer/       # Image display, zoom, thumbnail strip
├── services/     # ImageService, FileService, SecurityScopeService
└── models/       # FolderNode, ImageFile, ImageFormat
```

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Add Folder | `⌘O` |
| Save As (Export) | `⇧⌘S` |
| Delete | `⌫` |
| Reveal in Finder | `⌘R` |
| Copy to Clipboard | `⌘C` |
| Select All | `⌘A` |
| Toggle Sidebar | `⌥⌘S` |
| Back | `⌘[` |
| Previous File (Viewer) | `↑` |
| Next File (Viewer) | `↓` |
| Zoom In | `⌘+` |
| Zoom Out | `⌘-` |
| Actual Size | `⌘0` |
| Fit to Window | `⌘9` |
| Full Screen | `⌃⌘F` |

## License

MIT License — see [LICENSE](LICENSE) for details.

## Author

[@jenalab](https://www.jenalab.com)

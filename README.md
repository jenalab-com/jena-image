<p align="center">
  <img src="Resources/JenaImage-geometric-j-v11.png" alt="JenaImage" width="200">
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
- **Recursive Browsing** — Toggle in the sidebar header to show every image under the selected folder and all its subfolders as one flat grid
- **Grid / Masonry Browser** — Uniform grid cards by default (reading order stays obvious); switch to original-ratio masonry from the toolbar and the last choice is saved. Rounded cards sit on a light gray canvas whose color and opacity you can set in Preferences, beside a brighter sidebar, with adjustable thumbnail size, an optional transparency checkerboard toggle, filenames, folder navigation, and video play badges
- **Fast Thumbnails** — Visible cells load first in parallel with a skeleton placeholder; thumbnails persist in an on-disk HEIC cache (configurable 500 MB–8 GB) so they appear instantly on relaunch. Evicted iCloud Drive files are never downloaded just to make a thumbnail
- **Image Viewer** — In-panel viewer with zoom, rotate, flip (horizontal/vertical), and thumbnail strip navigation; sidebar syncs to current file
- **Color Palette & Magnifier** — Extract representative colors, adjust grouping tolerance, and copy HEX/RGB/approximate CMYK values. Toggle the pixel magnifier or hold Option (⌥) to sample original pixels and click to copy HEX.
- **Image Info** — `⌘I` shows file size, dimensions, DPI, color space, format, and EXIF camera/GPS data
- **Image Compare** — Select 2–4 images and view them side by side in a separate window with synchronized zoom/pan; swap any pane from a bottom candidate strip
- **Bookmarks** — Bookmark images from anywhere and collect them under a "Bookmarks" section in the sidebar; bookmarked images show a star badge in the grid. Remove, delete, or rename from the bookmark view; missing originals show a placeholder
- **Categories** — Collect images from different folders into named categories without moving originals. Assign one or multiple categories from the grid context menu or image viewer, and switch between folder and category browsing using the sidebar header icons
- **Similar Images** — Right-click an image to search within the current image list locally with Apple Vision Image Feature Print (revision 2). Browse up to 100 nearest matches and add selections to categories; saved features are reused until files or the model version change. No API key or separate model installation. [Model and usage](docs/image-similarity.md)
- **Web Panel** — The globe toolbar button opens a tabbed browser (system WebKit) between the folder sidebar and the image list, with Google/Bing/Naver web and image search. Links and sign-in pop-ups that open a new window open as new tabs, and ⌘-click or middle-click opens any link in a background tab (up to 30 tabs; a page can open at most two tabs per second); add a tab with the + button or **View → New Tab**. Sign-ins and the open tabs persist — on relaunch only the selected tab loads right away. Right-click a web image to save it into the folder you are browsing, or drag it onto the list, a folder tile, or a sidebar folder. The AI and web panels open one at a time. [Design](docs/web-panel-design.md)
- **Image Editing** — Crop, resize, canvas size, and color adjustment (brightness/contrast/saturation/highlights/shadows) with undo/redo; EXIF orientation handling and print support
- **Slideshow & QuickLook** — Auto-advancing slideshow and QuickLook preview
- **Video Player** — Play MP4, MOV, M4V, AVI, MKV files inline with AVKit
- **Format Conversion** — Export images to JPEG, PNG, WebP, HEIC, HEIF, AVIF, TIFF, BMP, GIF
- **File Management** — Rename, move, copy, duplicate, delete files with drag-and-drop support; sidebar context menu with Reveal in Finder, Rename, Export, Delete; open any file with a compatible app (or the macOS default app) from the context menu
- **In-App Updates** — **JenaImage → Check for Updates…** shows the latest GitHub release notes and installs it in place after verifying the download (SHA-256 and bundle identity), then relaunches
- **Keyboard Shortcuts** — Full keyboard support for all major operations

## Screenshots

<p align="center">
  <img src="docs/media/01-browser.png" alt="Masonry browser with folder sidebar" width="900">
</p>

| Image Viewer | Image Info |
|---|---|
| <img src="docs/media/03-viewer.png" alt="Image viewer with thumbnail sidebar" width="440"> | <img src="docs/media/04-info.png" alt="Image info window" width="300"> |
| **Image Compare** | **Categories** |
| <img src="docs/media/05-compare.png" alt="Compare three images side by side" width="440"> | <img src="docs/media/06-categories.png" alt="Category browsing" width="440"> |
| **Similar Images** | **AI Image Chat** |
| <img src="docs/media/07-similar.png" alt="Similar image search results" width="440"> | <img src="docs/media/08-ai-chat.png" alt="AI image chat panel with a reference image" width="440"> |
| **Web Panel** | **Save from the Web** |
| <img src="docs/media/09-web-panel.png" alt="Web panel with tabs between the sidebar and the image list, with a dragged web image saved to the folder" width="440"> | <img src="docs/media/10-web-save.png" alt="Right-click menu on a web image with a save-to-folder item" width="440"> |

### Demo

| Browse & View | Similar Images |
|---|---|
| <img src="docs/media/browse.gif" alt="Browsing, layout switching and viewer navigation" width="440"> | <img src="docs/media/similar.gif" alt="Finding similar images from the context menu" width="440"> |
| **Compare with synced zoom** | **AI image generation** |
| <img src="docs/media/compare.gif" alt="Comparing images with synchronized zoom" width="440"> | <img src="docs/media/ai.gif" alt="Generating an image from a reference with Codex (waiting time sped up)" width="440"> |
| **Collecting images from the web** | |
| <img src="docs/media/web.gif" alt="Opening the web panel, dragging a web image into a folder, saving another from the right-click menu and switching tabs" width="440"> | |

The UI is shown in Korean. Demo photos are from [Unsplash](docs/media/CREDITS.md); the web panel demo browses the [Lorem Picsum](https://picsum.photos/images) gallery of Unsplash photos. The AI demo's waiting time is sped up; actual generation took about two minutes.

## Requirements

- macOS 14.0 (Sonoma) or later

## Build

This project uses a Makefile-based build system — no Xcode project required.

```bash
# Clone
git clone https://github.com/jenalab-com/jena-image.git
cd jena-image

# Build
make build

# Unit tests and isolated category UI integration tests
make test
make test-ui

# Build and run
make run

# Install to /Applications (same destination as the DMG)
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
├── viewer/       # Image display, zoom, thumbnail strip, compare, editor
├── services/     # ImageService, FileService, SecurityScopeService
└── models/       # FolderNode, ImageFile, ImageFormat
```

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Add Folder | `⌘O` |
| Save As (Export) | `⇧⌘S` |
| Duplicate | `⌘D` |
| Print | `⌘P` |
| Show Info | `⌘I` |
| Delete | `⌫` |
| Reveal in Finder | `⌘R` |
| Copy to Clipboard | `⌘C` |
| Select All | `⌘A` |
| Compare Selected | `⌘\` |
| Toggle Bookmark | `⌘B` |
| Edit Image | `⌘E` |
| Toggle Sidebar | `⌥⌘S` |
| Back | `⌘[` |
| Previous File (Viewer) | `↑` |
| Next File (Viewer) | `↓` |
| Slideshow | `⌘↩` |
| Zoom In | `⌘+` |
| Zoom Out | `⌘-` |
| Actual Size | `⌘0` |
| Fit to Window | `⌘9` |
| Full Screen | `⌃⌘F` |

## License

MIT — Copyright (c) 2026 JenaLab. See [LICENSE](LICENSE).

## Author

[@jenalab](https://www.jenalab.com)

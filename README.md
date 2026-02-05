<p align="center">
  <img src="assets/icon.png" alt="BetterPasting Icon" width="128" height="128">
</p>

<h1 align="center">BetterPasting</h1>

<p align="center">
  <strong>A fast, keyboard-driven clipboard history manager for macOS with fuzzy search and multi-format support.</strong>
</p>

<p align="center">
  <img src="assets/better-pasting-demo.gif" alt="BetterPasting Demo" width="600">
</p>

---

## Features

- **Clipboard history** — Access your past copies instantly
- **Fuzzy search** — Type to filter clipboard items
- **Multi-format support** — Text, images, files, RTF, and HTML
- **Liquid Glass UI** — Native macOS 26 glass effect
- **Pin items** — Keep important clips at the top
- **Source tracking** — See which app each clip came from

## Installation

### Download
Grab the latest release from [Releases](https://github.com/user/BetterPasting/releases).

### Build from source
```bash
git clone https://github.com/user/BetterPasting.git
cd BetterPasting
./build-app.sh
```

### Permissions
BetterPasting requires:
- **Input Monitoring** — For global keyboard shortcuts

Grant these in **System Settings → Privacy & Security**.

## Usage

| Shortcut | Action |
|----------|--------|
| ⌘⇧V | Open clipboard history |
| ↑/↓ | Navigate items |
| Return | Paste selected item |
| Space | Quick Look preview |
| ⌘P | Pin/unpin item |
| Escape | Dismiss |
| Type | Filter with fuzzy search |

## Architecture

```
BetterPasting/
├── Sources/
│   ├── App/
│   │   ├── BetterPastingApp.swift    # Entry point, MenuBarExtra
│   │   ├── AppDelegate.swift         # Event handling, setup
│   │   └── AppState.swift            # Observable state
│   │
│   ├── Core/
│   │   ├── Clipboard/
│   │   │   ├── ClipboardMonitor.swift    # NSPasteboard polling
│   │   │   ├── ClipboardCopier.swift     # Paste to clipboard
│   │   │   └── ContentExtractor.swift    # Type detection & extraction
│   │   ├── EventTap/
│   │   │   ├── KeyboardEventTap.swift    # CGEventTap for global shortcuts
│   │   │   └── ModifierKeyTracker.swift  # Modifier key state
│   │   ├── Storage/
│   │   │   ├── ClipboardStore.swift      # Persistent storage
│   │   │   ├── ImageCache.swift          # Image file caching
│   │   │   └── CleanupManager.swift      # Cache cleanup
│   │   └── Permissions/
│   │       └── PermissionManager.swift   # Permission checks
│   │
│   ├── Services/
│   │   ├── ClipboardCache.swift      # Lock-free caching layer
│   │   ├── FuzzyMatcher.swift        # Search scoring
│   │   ├── SourceAppTracker.swift    # Track copy source
│   │   └── QuickLookManager.swift    # Preview generation
│   │
│   ├── Models/
│   │   ├── ClipboardItem.swift       # Item representation
│   │   ├── ContentType.swift         # Content type enum
│   │   └── UserPreferences.swift     # Settings persistence
│   │
│   └── UI/
│       ├── SidebarWindow/
│       │   ├── SidebarPanel.swift        # NSPanel overlay
│       │   ├── SidebarPanelManager.swift # Panel lifecycle
│       │   └── SidebarView.swift         # Main SwiftUI view
│       └── Components/
│           ├── GlassBackground.swift     # macOS glass effect
│           ├── ClipboardRowView.swift    # Item row
│           ├── ContentPreview.swift      # Content preview
│           ├── SearchBarView.swift       # Search input
│           └── KeyCap.swift              # Keyboard hint styling
```

### Key Components

**ClipboardMonitor** — Polls `NSPasteboard` for changes. Detects content type and extracts data via `ContentExtractor`.

**ClipboardCache** — Thread-safe cache with lock-free reads for UI responsiveness. Deduplicates by content hash.

**ContentExtractor** — Determines content type priority (RTF > HTML > Image > File > Text) and extracts appropriate data.

**SidebarPanel** — `NSPanel` subclass that slides in from the right. Stays on top, doesn't steal focus.

**FuzzyMatcher** — Scores matches by consecutive character bonuses and position weighting.

### Data Flow

```
ClipboardMonitor (polling)
      │
      ▼ (detects change)
ContentExtractor
      │
      ▼ (ClipboardItem)
ClipboardCache + ClipboardStore
      │
      ├─► AppState (ObservableObject)
      │
      └─► SidebarView (SwiftUI)
```

### Supported Content Types

| Type | Detection | Storage |
|------|-----------|---------|
| Text | `NSPasteboard.PasteboardType.string` | In-memory |
| Image | `tiff`, `png` types | Cached to disk |
| File | `fileURL` type | Path references |
| RTF | `rtf` type | Data blob |
| HTML | `html` type | String |

## Requirements

- macOS 15+
- Swift 5.9+

## License

MIT

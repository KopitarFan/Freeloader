# NuFinder

NuFinder is a small, native, open-source file manager for macOS. It keeps the
familiar column-free Finder layout while making paths and file operations
explicit.

## Current foundation

- Editable address bar with path and `~` expansion
- Real `⌘X` / `⌘V` move semantics inside NuFinder
- New-file action in the context menu
- Open-in-Terminal toolbar and context-menu actions
- Stable multi-criteria sorting
- File-operation panel with source, destination, bytes, speed, progress, and errors
- Optional expandable folder tree in the sidebar
- Automatic refresh when the current directory changes externally
- Inline rename, Duplicate, Quick Look, Get Info, and Reveal in Finder
- New Folder and hidden-file visibility toggle
- Undo for create, rename, copy, move, and Move to Trash
- Replace, Keep Both, and Skip conflict policies
- Pause, resume, and cancel controls between queued items
- Cross-volume move fallback and Option-drag copying
- Persistent tabs with independent back/forward history
- Breadcrumb navigation, recent locations, and path-history autocomplete
- Open folders in new tabs or windows
- Spring-loaded pane, Favorite, and tree folders during drag operations
- Shift-range, command-toggle, Select All, invert, and type-to-select
- List, compact, and icon views with per-folder column/sort preferences
- Current-folder and recursive search with contains, glob, regex, kind, size,
  and modification-date criteria
- Persistent saved searches
- Open With, Share, copy path/URL, folder sizing, and SHA-256 checksums
- Atomic batch rename with `{name}` and `{index}` tokens
- Undoable symbolic-link creation
- Configurable terminal application
- In-flight operation journal and recursive self-move protection

## Run

Requires macOS 15 and Xcode 16 or newer.

```sh
swift run NuFinder
```

For full app behavior, open `NuFinder.xcodeproj` and run the `NuFinder`
scheme. This builds a signed `.app` bundle and embeds the Finder Sync extension.
`Package.swift` remains available for fast command-line builds and tests.

Regenerate the Xcode project after adding source files:

```sh
ruby Scripts/generate_xcode_project.rb
```

## Direction

The project intentionally uses SwiftUI and AppKit rather than a browser runtime.
The Xcode app target supports Spotlight-backed scoped search, an embedded Finder
Sync extension with shared app-group configuration, chunk-level transfer
pause/cancel, and editable POSIX permissions and extended attributes. For a
local ad-hoc build without an Apple account, omit the app-group entitlements:

```sh
xcodebuild -project NuFinder.xcodeproj -scheme NuFinder \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  CODE_SIGN_ENTITLEMENTS= build
```

For Finder Sync communication, Developer ID distribution, and notarization,
select team `FLJNW3455S` in Xcode. If command-line signing cannot access it,
add the Apple ID that owns the “Miguel Rodriguez” team under Xcode → Settings
→ Accounts.

## Useful shortcuts

- `⌘X`, `⌘C`, `⌘V`: cut, copy, and paste
- `⌘Z`: undo the last supported file operation
- `⌘D`: duplicate
- `⌘I`: Get Info
- `Space`: Quick Look
- `Return`: rename
- `⌘Delete`: move to Trash
- `⌘⇧N`: new folder
- `⌘⌥N`: new file
- `⌘⇧.`: show or hide hidden files
- `⌘T`: new tab
- `⌘⇧T`: reopen the last closed tab
- `⌘W`: close tab (or window when only one tab remains)
- `⌘N`: new window
- `⌘⇧G`: focus Go to Folder
- `⌘[` / `⌘]`: back / forward

## License

MIT — see `LICENSE`.

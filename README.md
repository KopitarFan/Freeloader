# Freeloader

**A free file manager that actually pulls its weight.**

Finder alternatives want your money. Finder wants your patience. Freeloader
wants neither.

Freeloader is a native, free, open-source file manager for macOS. It provides
the file-management features that should not require a subscription—or a
support group.

[Website](https://kopitarfan.github.io/Freeloader/) ·
[Download Freeloader 0.2.10](https://github.com/KopitarFan/Freeloader/releases/download/v0.2.10/Freeloader-0.2.10.dmg)

Support: [miguel@miguelrodriguez.net](mailto:miguel@miguelrodriguez.net)

## Features

- Editable address bar with autocomplete and `~` expansion
- Real `⌘X` / `⌘V` file moves
- New-file and new-folder actions
- Open-in-Terminal toolbar and context-menu actions
- Stable multi-criteria sorting
- Detailed transfers with bytes, speed, progress, errors, pause, and cancel
- Optional expandable folder tree
- Drag and drop between the file pane, tree, and Favorites
- Tabs with independent back and forward history
- List, compact, and icon views
- Spotlight-backed recursive search
- SMB share mounting with recent servers and native macOS authentication
- Quick Look, Get Info, permissions, extended attributes, and checksums
- Undo for supported create, rename, copy, move, and Trash operations
- Embedded Finder Sync extension

## Requirements

- macOS 15 or newer
- Xcode 16 or newer when building from source

## Run from Xcode

Open `Freeloader.xcodeproj`, select the **Freeloader** scheme and **My Mac**,
then press `⌘R`.

## Run with Swift Package Manager

```sh
swift run Freeloader
```

## Tests

```sh
swift test
```

## Regenerate the Xcode project

The checked-in Xcode project is generated from the source tree:

```sh
ruby Scripts/generate_xcode_project.rb
```

## Useful shortcuts

- `⌘X`, `⌘C`, `⌘V`: cut, copy, and paste
- `⌘Z`: undo the last supported operation
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
- `⌘W`: close tab or window
- `⌘N`: new window
- `⌘⇧G`: focus Go to Folder
- `⌘K`: connect to an SMB server
- `⌘[` / `⌘]`: back / forward

## License

MIT. Free as in no invoice. Open as in no secrets.

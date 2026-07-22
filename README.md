# Katalog

A modern, opinionated ebook manager — Calibre reimagined as simple and zen.
*Simplicity by design, complexity by choice.*

Ghostty-style architecture: one shared **Rust core** + a fully **native
SwiftUI** UI. No cross-platform UI framework.

```
core/    Rust: epub parsing (rbook), SQLite library (rusqlite), transfer prep
macos/   SwiftUI app, links the core via a uniffi-generated xcframework
```

## Build & run (macOS, Apple Silicon)

```sh
./build-core.sh                 # builds the Rust core → dist/Katalog.xcframework
cd macos && swift run Katalog   # or: open Package.swift in Xcode and Run
```

Re-run `./build-core.sh` whenever the core's public API changes.

## Test the core

```sh
cargo test          # epub parse + library import/list/get/remove roundtrip
```

## MVP scope

- [x] EPUB metadata + cover extraction
- [x] Import into a managed library (copies file, caches cover, indexes in SQLite)
- [x] Transfer to Kindle over USB (mounted-volume detection + copy to `documents/`)

Out of scope for now: reading/rendering, format conversion, metadata editing,
online metadata, Send-to-Kindle email, Windows/Linux. The core stays
platform-agnostic so those slot in later.

## End-to-end check

1. `./build-core.sh && cd macos && swift run Katalog`
2. Click **+**, pick an `.epub` → cover appears in the grid.
3. Click a book → metadata detail.
4. Plug in a Kindle → **Send to Kindle** copies the file; confirm on-device.

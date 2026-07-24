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
make run     # rebuild core + bindings + app, then launch
```

Other targets: `make app` (full rebuild, no launch), `make core` (Rust core →
xcframework only), `make test`, `make clean`. Or open `macos/Package.swift` in
Xcode and Run (run `make core` once first so the xcframework exists).

## Test the core

```sh
make test     # epub parse + library import/list/get/remove roundtrip
```

## Scope

MVP, grouped by area. Checked = shipped.

**Library**
- [x] Import epubs — files, folders, drag-and-drop, Finder "Open With"
- [x] Managed library — copies file, caches cover, indexes in SQLite
- [x] Duplicate detection on import
- [x] Delete from library
- [x] Empty-library welcome screen
- [x] Configurable location + auto-organize into Author/Title folders

**Metadata**
- [x] View metadata + cover
- [x] Edit metadata (all fields + cover), written back into the epub
- [x] Online metadata lookup

**Formats & transfer**
- [x] EPUB parsing (read-only)
- [x] Native EPUB → MOBI conversion
- [x] Transfer to Kindle over USB + on-device detection

**Browse**
- [ ] Search
- [x] Sort by author / title
- [x] Two grid styles (compact / covers)
- [x] Follows system light / dark

### Ideas for later (or never)

- Automatic app updates (Sparkle) or App Store
- Send-to-Kindle email
- Windows / Linux (the Rust core is already platform-agnostic)
- In-app reading / rendering — Katalog is a manager, not a reader

## End-to-end check

1. `./build-core.sh && cd macos && swift run Katalog`
2. Click **+**, pick an `.epub` → cover appears in the grid.
3. Click a book → metadata detail.
4. Plug in a Kindle → **Send to Kindle** copies the file; confirm on-device.

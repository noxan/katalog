# MOBI converter gaps

Goal: Kindle-compatible output with equivalent reading/navigation behavior to
Calibre. Byte-for-byte parity is not required.

## P1 — Canonical MOBI6 structure

- [x] Set MOBI header constants at offsets `0xc4`, `0xe0`, `0xe8` and `0xec`
  to the MobileRead/Calibre values (`1`, `0xffffffff`, `0xffffffff`, `0xffffffff`).
- [x] Exclude final alignment padding from the declared EXTH length.
- [x] Write title, two null bytes, then align Record 0 to four bytes.
- [x] Prevent UTF-8 characters crossing text records, or emit multibyte-overlap
  trailing entries and set extra-data flag `0x1`.
- [x] Compare every fixed field and Record 0 boundary across representative Calibre files.

Plan: first use UTF-8-safe record boundaries, which needs no trailing-data
implementation. Normalize the four constants and padding in place, then add one
binary-layout regression test covering each offset.

Reference: <https://wiki.mobileread.com/wiki/MOBI> sections MOBI Header, EXTH
Header, Remainder of Record 0 and Multibyte character overlap.

## P2 — Navigation

- [x] Write MOBI6 `INDX` navigation records from the EPUB NCX/nav document.
- [x] Point `first_index_record` at them and preserve labels/order/targets.
- [x] Add TOC tests; verify generated navigation with Calibre.
- [x] Emit a flat NCX (like Calibre MOBI6) and an HTML `<guide>` toc reference so
  `ebook-convert` round-trips keep every declared entry (was dropping to ~29
  without `<guide>`; exact 4096-byte text records also required).
- [ ] Verify chapter jumps on a physical Kindle.

Note: EPUB nav can list more entries than we emit when some hrefs do not resolve
into the spine HTML; that gap is intentional, not a Calibre round-trip bug.

## P3 — Metadata

- [x] Preserve every creator/contributor as repeated EXTH author records.
- [x] Preserve language, publisher, publication date, subjects, contributors, rights and source.
- [x] Preserve series (EXTH 536) and series index (EXTH 537); ISBN already as EXTH 104.
- [x] Contributor roles: MOBI6 has no role tag — keep names as EXTH 108.
- [x] Add a metadata-rich test and compare `ebook-meta` output with Calibre.

Plan: add fields to `Source` only when they map to standard EXTH records, reuse
the existing EPUB parser, and emit repeated records for repeated values.

References: `mobi-rs` provides typed EXTH parsing/writing; `libmobi/meta.c` and
`766b/mobi/exth.go` provide the mature tag map. Do not emit fake ASIN/EBOK values:
they change Kindle shelf/cover behavior.

## P4 — Compatibility hardening

- [x] Test a multibyte character placed across the 4096-byte boundary.
- [x] Use exact 4096-byte text records (except last) so filepos/NCX math works.
- [ ] Add multibyte-overlap trailing data (flag `0x1`) if a split UTF-8 glyph shows up on device.
- [ ] Test small, large, image-heavy and metadata-rich books on a physical Kindle.

Plan: change one flag/data pair at a time and retain it only when it fixes a
reproducible reader failure.

Reference: MobileRead specifies flag `0x1` for a character crossing a record
boundary. `mobi-rs` and `libmobi` parse it; Calibre emits it. Avoiding split
characters is simpler and makes the flag unnecessary.

## P5 — Image handling

- [ ] Compare missing/extra images with Calibre and confirm they are only generated thumbnails or unused resources.
- [ ] Preserve reading-content images and cover references; do not chase identical record counts.

Plan: validate every emitted `recindex` and visually sample image-heavy books.

Reference: all surveyed implementations use `first_image_record + EXTH 201/202`;
separate thumbnails are optional. Match referenced content, not Calibre's count.

## Research notes

- `vv9k/mobi-rs`: useful Rust parser/header/EXTH oracle; not an EPUB→MOBI compiler
  and does not build NCX `INDX` records.
- `766b/mobi` and `efskap/mobi`: working MOBI6 writers with nested TOC support;
  old and lightly maintained, so copy the format model, not the dependency.
- `behringer24/mobi`: current Go MOBI/KF8 writer with clear record builders;
  useful implementation reference, but broader than Katalog needs.
- `bfabiszewski/libmobi`: mature parser and authoritative cross-check for INDX,
  EXTH and trailing-record decoding; primarily a reader/editor.
- `ciscoriordan/kindling`: actively maintained Rust compiler and excellent format
  notes; defaults to KF8/AZW3, so reuse encoding ideas rather than its architecture.

## Release check

- [x] Convert the complete Katalog library with both converters.
- [x] Require all Katalog MOBIs to round-trip through `ebook-convert`.
- [x] Compare metadata/TOC and normalized extracted text; document intentional differences.

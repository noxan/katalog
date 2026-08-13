# MOBI implementation comparison

Compared against Katalog's EPUB → MOBI6 converter in `core/src/mobi.rs`.
The target is reliable USB-sideloaded books, not full KF8 or byte parity.

| Implementation | Role | MOBI6 writer | PalmDOC | TOC/INDX | EXTH | Images | Trailing data | Best use for Katalog |
|---|---|---:|---:|---:|---:|---:|---:|---|
| Katalog | EPUB compiler | Yes | Write/read | Missing | Basic | Inline + cover | No | Baseline |
| `vv9k/mobi-rs` | Reader/header writer | No compiler | Read | Read header only | Typed read/write | Extract | Parse fields | Rust parsing oracle |
| `efskap/mobi` | Book writer/reader | Yes | Optional write | Nested NCX | Arbitrary records | Cover + thumbnail | No | TOC record model |
| `766b/mobi` | Forked writer/reader | Yes | Optional write | Nested NCX | Arbitrary records | Cover + thumbnail | No | TOC record model |
| `behringer24/mobi` | MOBI/KF8 writer | Yes | Write | NCX + KF8 indexes | Broad typed set | Cover + thumbnail | Yes | Clearest modern builders |
| `bfabiszewski/libmobi` | Reader/editor | No EPUB compiler | Read/write utilities | Full parser | Broad read/edit | Extract | Full parser | Independent validator |
| `ciscoriordan/kindling` | EPUB compiler | Mostly KF8/AZW3 | Write/read | Nested KF8 NCX | Broad | Cover/resources | Yes | Format tests and edge cases |
| Calibre `ebook-convert` | Reference compiler | Yes | Write/read | Full NCX | Broad | Optimized resources | Yes | Behavioral oracle |

## Where Katalog aligns

- Correct PalmDB wrapper, ascending record offsets and unique record IDs.
- MOBI6, UTF-8, 4096-byte independently PalmDOC-compressed text records.
- Standard Record 0 components and image `recindex` model.
- Correct `first_image`, last-content, FLIS, FCIS and EOF record relationships.
- Standard EXTH 100/103/104/201/202 records; repeated EXTH 100 preserves creators.
- Internal links use MOBI `filepos` byte offsets.
- All 55 library outputs are readable and round-trip through Calibre.

## Material gaps

### Canonical binary layout

MobileRead and all 55 Calibre outputs disagree with Katalog in four fixed MOBI
header values: Katalog writes zero at offsets `0xc4`, `0xe0`, `0xe8` and `0xec`;
the conventional values are respectively `1`, `0xffffffff`, `0xffffffff` and
`0xffffffff` (offsets from Record 0, including the PalmDOC header).

Katalog also includes alignment padding in the EXTH declared length, although
the format says the padding follows that length. It aligns the title before
adding its two terminator bytes; the conventional order is title, two nulls,
then four-byte alignment. Calibre additionally leaves more null slack in Record
0, but no known reader requires that slack.

These are accepted by Calibre but should be normalized before adding new record
types. They are small corrections and reduce ambiguity when debugging Kindle
indexing.

### Navigation

Katalog does not emit compiled NCX records or set `first_index_record`.
`efskap/mobi`, `766b/mobi`, `behringer24/mobi`, Kindling and Calibre do.

Minimum compatible model:

1. Primary `INDX` with a `TAGX` table.
2. Entry `INDX` with `IDXT` offsets and variable-width values.
3. `CNCX` string pool for labels.
4. Entries containing destination file position, label offset, depth and optional
   parent/first-child/last-child relationships.

Use `behringer24/mobi` for builder shape, `766b/mobi` for a small MOBI6 example,
and `libmobi/index.h` as the independent tag-number check. Do not copy either
Go writer wholesale: the old writer contains fixed padding/debug behavior and
the new writer also carries KF8 machinery Katalog does not need.

### Metadata

Katalog currently emits authors, description, ISBN and cover offsets. Other
writers commonly preserve publisher (101), subjects (105), publication date
(106), contributors (108), rights (109), source (112) and language (524).

Add only source-backed values. Do not synthesize ASIN (113) or document type
(501): modern Kindle firmware uses that pair for shelf and thumbnail behavior.
Series has no clean, universal MOBI6 mapping; keep it out unless a verified
reader behavior requires a convention.

### TOC destinations and text records

Katalog already computes final HTML byte offsets for internal links. Reuse
those offsets for NCX destinations. `filepos` is the relevant MOBI6 coordinate;
KF8 `pos:fid`, skeleton/chunk and TBS structures from newer writers do not apply.

### Trailing record data

Katalog sets `extra_record_data_flags = 0` and emits none. Calibre MOBI6 files
set bit 0 for UTF-8 overlap and may include TBS data; newer KF8 writers set bits
0 and 1. Katalog currently chunks raw UTF-8 bytes at 4096 bytes. A multibyte
character can therefore cross a record boundary; readers that decode records
independently may render a replacement character even though concatenating all
decompressed bytes succeeds.

The minimal fix is to move each boundary backward to a UTF-8 character boundary,
keeping zero flags. Multibyte-overlap entries are only needed if records must
split at exactly 4096 bytes. TBS remains unnecessary for Katalog's MOBI6 model.

### Images and thumbnails

Katalog preserves all EPUB manifest images and rewrites references. Other
writers may discard unused resources, generate a distinct thumbnail, or add
KF8 resource metadata. Different image counts are therefore not a defect.

Validate that each HTML `recindex` resolves and EXTH 201 points to the cover.
Generate a separate thumbnail only if physical Kindle library tiles require it.

## Recommended implementation order

1. Normalize fixed header values, EXTH/title padding and UTF-8 record boundaries.
2. MOBI6 NCX `INDX`/`CNCX`, including nested TOC tests.
3. Publisher, subject, date, contributor, rights, source and language EXTH data.
4. Full-library Calibre round-trip and physical-Kindle navigation test.
5. Only then investigate thumbnail differences with a failing fixture.

## Sources

- <https://github.com/vv9k/mobi-rs>
- <https://github.com/efskap/mobi>
- <https://github.com/766b/mobi>
- <https://github.com/behringer24/mobi>
- <https://github.com/bfabiszewski/libmobi>
- <https://github.com/ciscoriordan/kindling>
- <https://www.loc.gov/preservation/digital/formats/fdd/fdd000472.shtml>
- <https://wiki.mobileread.com/wiki/MOBI>

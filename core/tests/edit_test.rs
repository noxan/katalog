//! Metadata-edit tests. The first test is a spike that pins the one assumption
//! the whole feature rests on: rbook can round-trip an edited epub validly.

use std::io::Read;
use std::path::Path;

fn fixture() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/sample.epub")
}

/// Read the OPF (package document) text out of an epub, located the proper way:
/// META-INF/container.xml → first rootfile full-path.
fn read_opf_bytes(path: &Path) -> String {
    let f = std::fs::File::open(path).unwrap();
    let mut zip = zip::ZipArchive::new(f).unwrap();
    let container = {
        let mut e = zip.by_name("META-INF/container.xml").unwrap();
        let mut s = String::new();
        e.read_to_string(&mut s).unwrap();
        s
    };
    // Cheap attribute scrape — good enough for a test helper.
    let opf_path = container
        .split("full-path=")
        .nth(1)
        .and_then(|s| s.trim_start_matches(['"', '\'']).split(['"', '\'']).next())
        .expect("rootfile full-path");
    let mut e = zip.by_name(opf_path).unwrap();
    let mut s = String::new();
    e.read_to_string(&mut s).unwrap();
    s
}

/// The OCF invariant readers rely on: the first zip entry is `mimetype`,
/// STORED (uncompressed), holding exactly the epub media type.
fn assert_mimetype_first_stored(path: &Path) {
    let f = std::fs::File::open(path).unwrap();
    let mut zip = zip::ZipArchive::new(f).unwrap();
    let mut first = zip.by_index(0).unwrap();
    assert_eq!(first.name(), "mimetype", "first entry must be mimetype");
    assert_eq!(
        first.compression(),
        zip::CompressionMethod::Stored,
        "mimetype must be stored uncompressed"
    );
    let mut s = String::new();
    first.read_to_string(&mut s).unwrap();
    assert_eq!(s, "application/epub+zip");
}

use katalog::library::BookEdit;
use katalog::{Book, Library};
use std::sync::Arc;

fn fixture_str() -> String {
    fixture().to_string_lossy().into_owned()
}

fn lib_in(tmp: &Path) -> Arc<Library> {
    let db = tmp.join("library.db").to_string_lossy().into_owned();
    let books = tmp.join("books").to_string_lossy().into_owned();
    Library::open(db, books).unwrap()
}

/// A no-change edit derived from a book — tweak the fields a test cares about.
fn edit_from(b: &Book) -> BookEdit {
    BookEdit {
        title: b.title.clone(),
        authors: b.authors.clone(),
        series: b.series.clone(),
        series_index: b.series_index,
        publisher: b.publisher.clone(),
        isbn: b.isbn.clone(),
        language: b.language.clone(),
        description: b.description.clone(),
        cover: None,
        remove_cover: false,
    }
}

fn tiny_png() -> Vec<u8> {
    let img = image::RgbImage::from_pixel(2, 2, image::Rgb([9, 42, 123]));
    let mut buf = std::io::Cursor::new(Vec::new());
    img.write_to(&mut buf, image::ImageFormat::Png).unwrap();
    buf.into_inner()
}

/// Every editable field round-trips through the DB, and the text fields plus a
/// new cover round-trip back into the epub file itself (re-parse reads them).
#[test]
fn update_roundtrips_db_and_epub() {
    let tmp = tempfile::tempdir().unwrap();
    let lib = lib_in(tmp.path());
    let book = lib.import(fixture_str(), true, true).unwrap();

    let png = tiny_png();
    let edit = BookEdit {
        title: "New Title".into(),
        authors: vec!["Grace Hopper".into(), "Katherine Johnson".into()],
        series: Some("Pioneers".into()),
        series_index: Some(3.0),
        publisher: Some("Katalog Press".into()),
        isbn: Some("urn:isbn:9780000000002".into()),
        language: Some("fr".into()),
        description: Some("Rewritten blurb.".into()),
        cover: Some(png.clone()),
        remove_cover: false,
    };
    let updated = lib.update(book.id, edit).unwrap();

    // DB reflects everything.
    assert_eq!(updated.title, "New Title");
    assert_eq!(updated.authors, vec!["Grace Hopper", "Katherine Johnson"]);
    assert_eq!(updated.series.as_deref(), Some("Pioneers"));
    assert_eq!(updated.series_index, Some(3.0));
    assert_eq!(updated.publisher.as_deref(), Some("Katalog Press"));
    assert_eq!(updated.isbn.as_deref(), Some("urn:isbn:9780000000002"));
    assert_eq!(updated.language.as_deref(), Some("fr"));
    assert_eq!(updated.description.as_deref(), Some("Rewritten blurb."));
    assert_eq!(lib.get(book.id).unwrap().unwrap().title, "New Title");

    // Cached cover file (what the UI shows) holds the exact new bytes.
    let cached = std::fs::read(updated.cover_path.as_ref().unwrap()).unwrap();
    assert_eq!(cached, png);

    // File on disk carries the edited metadata back.
    let re = katalog::epub::parse(Path::new(&updated.file_path)).unwrap();
    assert_eq!(re.title, "New Title");
    assert_eq!(re.authors, vec!["Grace Hopper", "Katherine Johnson"]);
    assert_eq!(re.language.as_deref(), Some("fr"));
    assert_eq!(re.publisher.as_deref(), Some("Katalog Press"));
    assert!(re.description.unwrap().contains("Rewritten"));
    assert!(re.cover.map(|c| !c.is_empty()).unwrap_or(false));
    assert_mimetype_first_stored(Path::new(&updated.file_path));
}

/// Removing the cover clears the cached file, the indexed path, and the cover
/// out of the epub itself.
#[test]
fn update_removes_cover() {
    let tmp = tempfile::tempdir().unwrap();
    let lib = lib_in(tmp.path());
    let book = lib.import(fixture_str(), true, true).unwrap();
    assert!(book.cover_path.is_some(), "fixture has a cover to remove");
    let cached = book.cover_path.clone().unwrap();

    let mut edit = edit_from(&book);
    edit.remove_cover = true;
    let updated = lib.update(book.id, edit).unwrap();

    assert_eq!(updated.cover_path, None, "cover_path cleared");
    assert!(!Path::new(&cached).exists(), "cached cover file removed");
    assert!(
        katalog::epub::parse(Path::new(&updated.file_path)).unwrap().cover.is_none(),
        "cover gone from the epub"
    );
}

/// A new cover lands at a different cover_path (so the UI reloads it) and the
/// old cached file is cleaned up.
#[test]
fn update_new_cover_changes_path_and_prunes_old() {
    let tmp = tempfile::tempdir().unwrap();
    let lib = lib_in(tmp.path());
    let book = lib.import(fixture_str(), true, true).unwrap();
    let old = book.cover_path.clone().unwrap();

    let mut edit = edit_from(&book);
    edit.cover = Some(tiny_png());
    let updated = lib.update(book.id, edit).unwrap();

    let new = updated.cover_path.clone().unwrap();
    assert_ne!(new, old, "cover_path must change so SwiftUI reloads");
    assert!(Path::new(&new).exists());
    assert!(!Path::new(&old).exists(), "old cached cover pruned");
}

/// Series and its position are stored in the EPUB using Calibre-compatible
/// metadata, as well as in the library index.
#[test]
fn update_series_writes_epub_metadata() {
    let tmp = tempfile::tempdir().unwrap();
    let lib = lib_in(tmp.path());
    let book = lib.import(fixture_str(), true, true).unwrap();

    let mut edit = edit_from(&book);
    edit.series = Some("Zzarquon Saga".into());
    edit.series_index = Some(2.5);
    let updated = lib.update(book.id, edit).unwrap();

    assert_eq!(updated.series.as_deref(), Some("Zzarquon Saga"));
    assert_eq!(updated.series_index, Some(2.5));
    let opf = read_opf_bytes(Path::new(&updated.file_path));
    // EPUB 3 collection metadata is primary; Calibre fields remain as a
    // compatibility fallback for older readers and metadata tools.
    assert!(opf.contains("belongs-to-collection") && opf.contains("Zzarquon Saga"));
    assert!(opf.contains("collection-type") && opf.contains("series"));
    assert!(opf.contains("group-position") && opf.contains("2.5"));
    assert!(opf.contains("calibre:series") && opf.contains("Zzarquon Saga"));
    assert!(opf.contains("calibre:series_index") && opf.contains("2.5"));

    // Re-importing the edited file finds the persisted metadata.
    let second = lib.import(updated.file_path.clone(), true, false).unwrap();
    assert_eq!(second.series.as_deref(), Some("Zzarquon Saga"));
    assert_eq!(second.series_index, Some(2.5));
}

/// Clearing an optional field to empty stores NULL and removes it from the file.
#[test]
fn update_clears_publisher() {
    let tmp = tempfile::tempdir().unwrap();
    let lib = lib_in(tmp.path());
    let book = lib.import(fixture_str(), true, true).unwrap();

    let mut set = edit_from(&book);
    set.publisher = Some("Temp Publisher".into());
    lib.update(book.id, set).unwrap();

    let mut clear = edit_from(&lib.get(book.id).unwrap().unwrap());
    clear.publisher = None;
    let updated = lib.update(book.id, clear).unwrap();

    assert_eq!(updated.publisher, None);
    let opf = read_opf_bytes(Path::new(&updated.file_path));
    assert!(!opf.contains("Temp Publisher"), "publisher removed from OPF");
}

/// Organized layout: editing the title moves the managed file to its new
/// Author/Title path, prunes the emptied dir, and updates the indexed path.
#[test]
fn update_reorganizes_on_title_change() {
    let tmp = tempfile::tempdir().unwrap();
    let lib = lib_in(tmp.path());
    let book = lib.import(fixture_str(), true, true).unwrap();
    let old_path = book.file_path.clone();

    let mut edit = edit_from(&book);
    edit.title = "Totally Different".into();
    let updated = lib.update(book.id, edit).unwrap();

    assert_ne!(updated.file_path, old_path);
    assert!(Path::new(&updated.file_path).exists(), "moved to new path");
    assert!(!Path::new(&old_path).exists(), "old path gone");
    assert!(
        updated.file_path.ends_with("Totally Different - Ada Lovelace.epub"),
        "renamed: {}",
        updated.file_path
    );
}

/// Editing only the description leaves an organized file exactly where it was.
#[test]
fn update_description_only_does_not_move() {
    let tmp = tempfile::tempdir().unwrap();
    let lib = lib_in(tmp.path());
    let book = lib.import(fixture_str(), true, true).unwrap();

    let mut edit = edit_from(&book);
    edit.description = Some("Just a new blurb.".into());
    let updated = lib.update(book.id, edit).unwrap();

    assert_eq!(updated.file_path, book.file_path, "file stays put");
    assert!(Path::new(&updated.file_path).exists());
}

/// Flat (unorganized) imports keep their filename even when title/author change.
#[test]
fn update_flat_import_does_not_move() {
    let tmp = tempfile::tempdir().unwrap();
    let lib = lib_in(tmp.path());
    let book = lib.import(fixture_str(), true, false).unwrap();

    let mut edit = edit_from(&book);
    edit.title = "Renamed".into();
    edit.authors = vec!["Someone Else".into()];
    let updated = lib.update(book.id, edit).unwrap();

    assert_eq!(updated.file_path, book.file_path, "flat file not moved");
    assert!(Path::new(&updated.file_path).exists());
    // ...but the metadata was still written into it.
    assert_eq!(katalog::epub::parse(Path::new(&updated.file_path)).unwrap().title, "Renamed");
}

/// In-place (copy=false) imports are edited where they live and never moved.
#[test]
fn update_in_place_edits_but_never_moves() {
    let tmp = tempfile::tempdir().unwrap();
    let lib = lib_in(tmp.path());
    // Copy the fixture somewhere outside the library so we can edit it freely.
    let external = tmp.path().join("outside.epub");
    std::fs::copy(fixture(), &external).unwrap();
    let book = lib.import(external.to_string_lossy().into_owned(), false, true).unwrap();

    let mut edit = edit_from(&book);
    edit.title = "Edited In Place".into();
    let updated = lib.update(book.id, edit).unwrap();

    assert_eq!(updated.file_path, external.to_string_lossy());
    assert_eq!(katalog::epub::parse(&external).unwrap().title, "Edited In Place");
}

/// Updating an unknown id errors and touches nothing.
#[test]
fn update_missing_id_errors() {
    let tmp = tempfile::tempdir().unwrap();
    let lib = lib_in(tmp.path());
    let book = lib.import(fixture_str(), true, true).unwrap();

    let mut edit = edit_from(&book);
    edit.title = "ghost".into();
    assert!(lib.update(9999, edit).is_err());
    assert_eq!(lib.get(book.id).unwrap().unwrap().title, book.title);
}

/// Filesystem-unsafe and unicode characters are sanitized in the path but kept
/// verbatim inside the epub metadata.
#[test]
fn update_sanitizes_path_keeps_raw_title() {
    let tmp = tempfile::tempdir().unwrap();
    let lib = lib_in(tmp.path());
    let book = lib.import(fixture_str(), true, true).unwrap();

    let mut edit = edit_from(&book);
    edit.title = "A/B: Café?".into();
    let updated = lib.update(book.id, edit).unwrap();

    let name = Path::new(&updated.file_path).file_name().unwrap().to_str().unwrap();
    assert!(!name.contains('/') && !name.contains(':') && !name.contains('?'), "sanitized: {name}");
    assert_eq!(katalog::epub::parse(Path::new(&updated.file_path)).unwrap().title, "A/B: Café?");
}

/// Spike: prove rbook edits an existing epub and re-parses cleanly, is
/// idempotent (no duplicate creators on re-edit), and keeps the OCF invariant.
/// Everything else in the feature depends on this holding.
#[test]
fn rbook_roundtrip_spike() {
    let tmp = tempfile::tempdir().unwrap();
    let out = tmp.path().join("edited.epub");

    let edit = |src: &Path, dst: &Path| {
        let mut epub = rbook::Epub::open(src).expect("open epub");
        epub.edit()
            .clear_meta("dc:title")
            .title("Edited Title")
            .clear_meta("dc:creator")
            .author(["Grace Hopper", "Katherine Johnson"])
            .clear_meta("dc:description")
            .description("A freshly edited description.")
            .clear_meta("dc:language")
            .language("fr")
            .modified_now()
            .write()
            .save(dst)
            .expect("save edited epub");
    };

    edit(&fixture(), &out);

    let e = katalog::epub::parse(&out).expect("re-parse edited epub");
    assert_eq!(e.title, "Edited Title");
    assert_eq!(e.authors, vec!["Grace Hopper", "Katherine Johnson"]);
    assert_eq!(e.language.as_deref(), Some("fr"));
    assert!(e.description.unwrap().contains("freshly edited"));
    assert!(e.cover.map(|c| !c.is_empty()).unwrap_or(false), "cover survived");
    assert_mimetype_first_stored(&out);

    // Idempotence: editing the already-edited file must not accumulate creators.
    let out2 = tmp.path().join("edited2.epub");
    edit(&out, &out2);
    let e2 = katalog::epub::parse(&out2).unwrap();
    assert_eq!(e2.authors, vec!["Grace Hopper", "Katherine Johnson"], "no duplicate creators");
    let opf = read_opf_bytes(&out2);
    assert_eq!(opf.matches("<dc:creator").count(), 2, "exactly two dc:creator elements");
}

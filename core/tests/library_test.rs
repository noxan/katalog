use std::path::Path;

fn fixture() -> String {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/sample.epub")
        .to_string_lossy()
        .into_owned()
}

#[test]
fn import_list_get_remove_roundtrip() {
    let tmp = tempfile::tempdir().unwrap();
    let db = tmp.path().join("library.db").to_string_lossy().into_owned();
    let books = tmp.path().join("books").to_string_lossy().into_owned();

    let lib = katalog::Library::open(db, books).unwrap();

    // import (copy + organize)
    let book = lib.import(fixture(), true, true).unwrap();
    assert_eq!(book.title, "The Zen of Katalog");
    assert_eq!(book.authors, vec!["Ada Lovelace", "Alan Turing"]);
    assert!(Path::new(&book.file_path).exists(), "epub copied into library");
    let cover = book.cover_path.clone().expect("cover cached");
    assert!(Path::new(&cover).exists(), "cover written");

    // list + get
    assert_eq!(lib.list().unwrap().len(), 1);
    assert_eq!(lib.get(book.id).unwrap().unwrap().title, book.title);

    // transfer prep returns the managed path
    assert_eq!(lib.prepare_transfer(book.id).unwrap(), book.file_path);

    // remove deletes row and managed folder
    lib.remove(book.id).unwrap();
    assert!(lib.list().unwrap().is_empty());
    assert!(lib.get(book.id).unwrap().is_none());
    assert!(!Path::new(&book.file_path).exists(), "managed file removed");
}

#[test]
fn find_duplicate_matches_existing_and_carries_preview() {
    let tmp = tempfile::tempdir().unwrap();
    let db = tmp.path().join("library.db").to_string_lossy().into_owned();
    let books = tmp.path().join("books").to_string_lossy().into_owned();

    let lib = katalog::Library::open(db, books).unwrap();

    // No library yet → no duplicate.
    assert!(lib.find_duplicate(fixture()).unwrap().is_none());

    let book = lib.import(fixture(), true, true).unwrap();

    // Re-importing the same epub is now flagged as a duplicate.
    let hit = lib.find_duplicate(fixture()).unwrap().expect("duplicate found");
    assert_eq!(hit.existing.id, book.id);
    assert_eq!(hit.incoming_title, "The Zen of Katalog");
    assert!(hit.incoming_cover.map(|c| !c.is_empty()).unwrap_or(false));
}

#[test]
fn import_in_place_does_not_copy_or_delete_source() {
    let tmp = tempfile::tempdir().unwrap();
    let db = tmp.path().join("library.db").to_string_lossy().into_owned();
    let books = tmp.path().join("books").to_string_lossy().into_owned();

    // A source epub living OUTSIDE the library folder.
    let external = tmp.path().join("external.epub");
    std::fs::copy(fixture(), &external).unwrap();
    let external = external.to_string_lossy().into_owned();

    let lib = katalog::Library::open(db, books).unwrap();
    let book = lib.import(external.clone(), false, false).unwrap();

    // Referenced in place: file_path is the original, still there.
    assert_eq!(book.file_path, external);
    assert!(book.cover_path.is_some(), "cover cached even without copy");

    // Removing must NOT delete the user's original file.
    lib.remove(book.id).unwrap();
    assert!(Path::new(&external).exists(), "external source preserved on remove");
}

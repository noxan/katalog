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

    // import
    let book = lib.import(fixture()).unwrap();
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

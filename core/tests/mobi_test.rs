use std::path::Path;

fn fixture() -> String {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/sample.epub")
        .to_string_lossy()
        .into_owned()
}

#[test]
fn converts_epub_to_readable_mobi() {
    let tmp = tempfile::tempdir().unwrap();
    let out = tmp.path().join("book.mobi");
    let out_s = out.to_string_lossy().into_owned();

    katalog::mobi::epub_to_mobi(&fixture(), &out_s).expect("convert");

    // Oracle: the `mobi` crate must parse what we wrote.
    let m = mobi::Mobi::from_path(&out).expect("mobi crate reads our output");
    assert_eq!(m.title(), "The Zen of Katalog");
    assert_eq!(m.author().as_deref(), Some("Ada Lovelace"));
    assert_eq!(m.isbn().as_deref(), Some("urn:isbn:9781234567897"));

    // The chapter text must survive into the MOBI text records. (We scan raw
    // records rather than content_as_string: the crate's range() drops the last
    // record, which empties a single-record book — our layout matches real
    // Kindle mobis, verified against a device file.)
    let text: String = m
        .raw_records()
        .records()
        .iter()
        .map(|r| String::from_utf8_lossy(r.content))
        .collect();
    assert!(text.contains("Hello"), "chapter body text present");
    assert!(text.contains("Chapter 1"), "chapter heading present");
}

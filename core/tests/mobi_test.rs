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

    // The chapter text must survive into the (PalmDOC-compressed) first text
    // record. We decompress it ourselves: the crate's content_as_string works
    // but its range() drops the last record, emptying a single-record book.
    let recs = m.raw_records();
    let record1 = recs.records()[1].content;
    let text = String::from_utf8_lossy(&katalog::mobi::palmdoc_decompress(record1)).into_owned();
    assert!(text.contains("Hello"), "chapter body text present: {text:?}");
    assert!(text.contains("Chapter 1"), "chapter heading present");
}

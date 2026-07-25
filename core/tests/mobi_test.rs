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
    assert_eq!(m.isbn().as_deref(), Some("9781234567897"));

    // The chapter text must survive into the (PalmDOC-compressed) first text
    // record. We decompress it ourselves: the crate's content_as_string works
    // but its range() drops the last record, emptying a single-record book.
    let recs = m.raw_records();
    let record1 = recs.records()[1].content;
    let text = String::from_utf8_lossy(&katalog::mobi::palmdoc_decompress(record1)).into_owned();
    assert!(text.contains("Hello"), "chapter body text present: {text:?}");
    assert!(text.contains("Chapter 1"), "chapter heading present");
}

#[test]
fn internal_links_become_correct_filepos() {
    let epub = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/nav.epub");
    let tmp = tempfile::tempdir().unwrap();
    let out = tmp.path().join("nav.mobi");
    katalog::mobi::epub_to_mobi(&epub.to_string_lossy(), &out.to_string_lossy()).unwrap();

    // Reconstruct the uncompressed text (small fixture => single text record 1).
    let m = mobi::Mobi::from_path(&out).unwrap();
    let recs = m.raw_records();
    let text = katalog::mobi::palmdoc_decompress(recs.records()[1].content);
    let text = String::from_utf8_lossy(&text);

    // Every internal link resolved to a non-zero, in-bounds byte offset...
    let mut filepos = Vec::new();
    for (i, _) in text.match_indices("filepos=\"") {
        let v = &text[i + 9..i + 19];
        filepos.push(v.parse::<usize>().unwrap());
    }
    assert_eq!(filepos.len(), 2, "two internal links rewritten");
    assert!(filepos.iter().all(|&o| o > 0 && o < text.len()), "offsets in bounds: {filepos:?}");

    // ...and the #mid link points exactly at the <p id="mid"> element.
    let mid = text.find("<p id=\"mid\"").expect("mid anchor present");
    assert!(filepos.contains(&mid), "a filepos targets the #mid anchor at {mid}: {filepos:?}");
    // No internal href left behind for the rewritten links.
    assert!(!text.contains("href=\"ch2.xhtml"), "internal href replaced");
}

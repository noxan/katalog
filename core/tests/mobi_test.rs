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

    // The chapter text must survive into the first uncompressed text record.
    let recs = m.raw_records();
    let record1 = recs.records()[1].content;
    let text = String::from_utf8_lossy(record1).into_owned();
    assert!(text.contains("Hello"), "chapter body text present: {text:?}");
    assert!(text.contains("Chapter 1"), "chapter heading present");
}

#[test]
fn container_ids_and_content_range_are_valid() {
    let tmp = tempfile::tempdir().unwrap();
    let out = tmp.path().join("book.mobi");
    katalog::mobi::epub_to_mobi(&fixture(), &out.to_string_lossy()).unwrap();
    let data = std::fs::read(out).unwrap();
    let u16_at = |n| u16::from_be_bytes(data[n..n + 2].try_into().unwrap());
    let u32_at = |n| u32::from_be_bytes(data[n..n + 4].try_into().unwrap());
    let records = u16_at(76) as usize;
    let record0 = u32_at(78) as usize;
    assert_eq!(u16_at(record0), 1, "text records are uncompressed");
    let max_id = (0..records)
        .map(|i| u32::from_be_bytes([0, data[83 + i * 8], data[84 + i * 8], data[85 + i * 8]]))
        .max().unwrap();
    assert!(u32_at(68) > max_id, "PDB unique-ID seed follows assigned IDs");
    let mobi = record0 + 16;
    let flis = u32_at(mobi + 192);
    assert_eq!(u16_at(mobi + 178) as u32, flis - 1, "content ends before FLIS");
}

#[test]
fn internal_links_become_correct_filepos() {
    let epub = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/nav.epub");
    let tmp = tempfile::tempdir().unwrap();
    let out = tmp.path().join("nav.mobi");
    katalog::mobi::epub_to_mobi(&epub.to_string_lossy(), &out.to_string_lossy()).unwrap();

    // Small fixture => single text record 1.
    let m = mobi::Mobi::from_path(&out).unwrap();
    let recs = m.raw_records();
    let text = String::from_utf8_lossy(recs.records()[1].content);

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

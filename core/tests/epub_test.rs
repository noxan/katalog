use std::path::Path;

#[test]
fn parses_metadata_and_cover() {
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/sample.epub");
    let e = katalog::epub::parse(&fixture).expect("parse fixture");

    assert_eq!(e.title, "The Zen of Katalog");
    assert_eq!(e.authors, vec!["Ada Lovelace", "Alan Turing"]);
    assert_eq!(e.language.as_deref(), Some("en"));
    // Stored bare: the fixture writes it as urn:isbn:9781234567897.
    assert_eq!(e.isbn.as_deref(), Some("9781234567897"));
    assert!(e.page_count < 0, "fixture has no declared page list");
    assert!(e.description.is_some());
    assert!(e.cover.map(|c| !c.is_empty()).unwrap_or(false), "cover extracted");
}

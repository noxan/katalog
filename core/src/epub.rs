//! EPUB metadata + cover extraction. Pure Rust, no FFI — testable in isolation.

use std::path::Path;

/// Metadata pulled straight out of an epub, before it becomes a library row.
#[derive(Debug, Clone)]
pub struct ParsedEpub {
    pub title: String,
    pub authors: Vec<String>,
    pub language: Option<String>,
    pub publisher: Option<String>,
    pub isbn: Option<String>,
    pub description: Option<String>,
    pub cover: Option<Vec<u8>>,
}

pub fn parse(path: &Path) -> Result<ParsedEpub, String> {
    let epub = rbook::Epub::open(path).map_err(|e| format!("open epub: {e}"))?;
    let md = epub.metadata();

    let title = md
        .title()
        .map(|t| t.value().to_string())
        .unwrap_or_else(|| fallback_title(path));

    let authors: Vec<String> = md.creators().map(|c| c.value().to_string()).collect();

    let cover = epub
        .manifest()
        .cover_image()
        .and_then(|entry| entry.read_bytes().ok())
        .map(|b| b.to_vec());

    Ok(ParsedEpub {
        title,
        authors,
        language: md.language().map(|l| l.value().to_string()),
        // ponytail: rbook 0.7 has no direct dc:publisher accessor; skip until needed.
        publisher: None,
        isbn: md.identifier().map(|i| i.value().to_string()),
        description: md.description().map(|d| d.value().to_string()),
        cover,
    })
}

fn fallback_title(path: &Path) -> String {
    path.file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Untitled")
        .to_string()
}

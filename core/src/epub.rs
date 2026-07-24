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
    let publisher = md.by_property("dc:publisher").next().map(|p| p.value().to_string());

    let cover = epub
        .manifest()
        .cover_image()
        .and_then(|entry| entry.read_bytes().ok())
        .map(|b| b.to_vec());

    Ok(ParsedEpub {
        title,
        authors,
        language: md.language().map(|l| l.value().to_string()),
        publisher,
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

/// Write edited metadata back into an epub's package document (OPF), in place.
/// The metadata `write_metadata` writes into an epub. Deliberately narrower than
/// the library's `BookEdit`: ISBN and series are omitted because they are NOT
/// written to the file (the DB is authoritative). ISBN lives in `dc:identifier`,
/// often the package `unique-identifier` — rewriting it risks breaking that link;
/// series has no standard `dc:` slot. Optional fields are `None` when cleared.
pub struct EpubEdit<'a> {
    pub title: &'a str,
    pub authors: &'a [String],
    pub publisher: Option<&'a str>,
    pub language: Option<&'a str>,
    pub description: Option<&'a str>,
    pub cover: Option<&'a [u8]>,
    pub remove_cover: bool,
}

/// Write edited metadata back into an epub's package document (OPF), in place.
/// rbook's editor preserves every other resource and keeps the OCF invariants
/// valid for EPUB 2 and 3 (mimetype-first/stored, refreshed dcterms:modified).
pub fn write_metadata(path: &Path, edit: &EpubEdit) -> Result<(), String> {
    let mut epub = rbook::Epub::open(path).map_err(|e| format!("open epub: {e}"))?;

    // Cover: remove takes precedence; otherwise replace an existing cover's bytes
    // in place (like Calibre) so we don't add a duplicate manifest entry. If
    // there's no cover yet, a new one is added via the editor below.
    let has_cover = epub.manifest().cover_image().is_some();
    if edit.remove_cover {
        if let Some(cover_id) = epub.manifest().cover_image().map(|c| c.id().to_string()) {
            epub.manifest_mut().remove_by_id(&cover_id);
        }
    } else if let Some(bytes) = edit.cover {
        if has_cover {
            if let Some(mut entry) = epub.manifest_mut().cover_image_mut() {
                entry.set_content(bytes.to_vec());
            }
        }
    }

    // Editor setters append, so clear the field before setting to get replace
    // semantics (see rbook `clear_meta` docs).
    let mut editor = epub.edit().clear_meta("dc:title").title(edit.title);
    editor = editor.clear_meta("dc:creator");
    for author in edit.authors {
        editor = editor.author(author.as_str());
    }
    // Optional text fields: replace when provided, remove when cleared.
    editor = editor.clear_meta("dc:description");
    if let Some(d) = edit.description {
        editor = editor.description(d);
    }
    editor = editor.clear_meta("dc:publisher");
    if let Some(p) = edit.publisher {
        editor = editor.publisher(p);
    }
    // dc:language is required for a valid epub, so only replace it when a value
    // is given — never clear it to nothing.
    if let Some(l) = edit.language {
        editor = editor.clear_meta("dc:language").language(l);
    }
    if edit.remove_cover {
        // Drop the legacy EPUB2 `<meta name="cover">` pointer too.
        editor = editor.clear_meta("cover");
    } else if let Some(bytes) = edit.cover {
        if !has_cover {
            // No existing cover — add a fresh one.
            let name = format!("cover.{}", cover_ext(bytes));
            editor = editor.cover_image((name.as_str(), bytes.to_vec()));
        }
    }

    // Atomic: write to a sibling temp file, then rename over the original.
    let tmp = path.with_extension("epub.tmp");
    editor
        .modified_now()
        .write()
        .save(&tmp)
        .map_err(|e| format!("save epub: {e}"))?;
    std::fs::rename(&tmp, path).map_err(|e| format!("replace epub: {e}"))?;
    Ok(())
}

/// Extension for a cover image, sniffed from its bytes so the epub manifest's
/// media-type matches the content. Falls back to jpg.
fn cover_ext(bytes: &[u8]) -> &'static str {
    match image::guess_format(bytes) {
        Ok(image::ImageFormat::Png) => "png",
        Ok(image::ImageFormat::Gif) => "gif",
        Ok(image::ImageFormat::WebP) => "webp",
        _ => "jpg",
    }
}

//! EPUB metadata + cover extraction. Pure Rust, no FFI — testable in isolation.

use std::path::Path;

use rbook::epub::metadata::DetachedEpubMetaEntry;

/// Metadata pulled straight out of an epub, before it becomes a library row.
#[derive(Debug, Clone)]
pub struct ParsedEpub {
    pub title: String,
    pub authors: Vec<String>,
    pub language: Option<String>,
    pub publisher: Option<String>,
    pub subjects: Vec<String>,
    pub publication_date: Option<String>,
    pub contributors: Vec<String>,
    pub rights: Option<String>,
    pub source: Option<String>,
    pub isbn: Option<String>,
    pub description: Option<String>,
    /// Calibre-compatible series metadata, when supplied by the EPUB.
    pub series: Option<String>,
    pub series_index: Option<f64>,
    /// Positive for an EPUB page-list count; negative for a word-count estimate.
    pub page_count: i64,
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
    let subjects = md.tags().map(|s| s.value().to_string()).collect();
    let publication_date = md.published_entry().map(|d| d.value().to_string());
    let contributors = md.contributors().map(|c| c.value().to_string()).collect();
    let rights = md.rights().next().map(|r| r.value().to_string());
    let source = md.by_property("dc:source").next().map(|s| s.value().to_string());

    // Prefer a real ISBN from any dc:identifier; the package's unique-identifier
    // is usually a uuid, useless for lookup and dedup. Store nothing rather
    // than a uuid when no ISBN is present.
    let isbn = md.identifiers().find_map(|i| isbn_from(i.value()));

    let cover = epub
        .manifest()
        .cover_image()
        .and_then(|entry| entry.read_bytes().ok())
        .map(|b| b.to_vec());
    // EPUB 3 collection metadata is authoritative. A series is a
    // `belongs-to-collection` entry refined as collection-type=series, with its
    // position in group-position. Fall back to Calibre's EPUB 2 convention for
    // the large existing ecosystem that still emits it.
    let epub3_series = md.by_property("belongs-to-collection").find_map(|entry| {
        let is_series = entry
            .refinements()
            .by_property("collection-type")
            .any(|kind| kind.value().eq_ignore_ascii_case("series"));
        is_series.then(|| {
            let index = entry
                .refinements()
                .by_property("group-position")
                .next()
                .and_then(|position| position.value().trim().parse().ok());
            (entry.value().to_string(), index)
        })
    });
    let (series, series_index) = epub3_series.unwrap_or_else(|| {
        let series = md.by_property("calibre:series").next().map(|s| s.value().to_string());
        let index = md
            .by_property("calibre:series_index")
            .next()
            .and_then(|i| i.value().trim().parse().ok());
        (series.unwrap_or_default(), index)
    });
    let series = (!series.is_empty()).then_some(series);

    Ok(ParsedEpub {
        title,
        authors,
        language: md.language().map(|l| l.value().to_string()),
        publisher,
        subjects,
        publication_date,
        contributors,
        rights,
        source,
        isbn,
        description: md.description().map(|d| d.value().to_string()),
        // `calibre:series` and `calibre:series_index` are the de facto EPUB
        // convention used by Calibre and most metadata tools. They work in both
        // EPUB 2 and 3, unlike EPUB 3 collection refinements.
        series,
        series_index,
        page_count: epub
            .toc()
            .by_kind("page-list")
            .map(|pages| pages.flatten().count() as i64)
            .unwrap_or_else(|| -estimated_pages(&epub)),
        cover,
    })
}

/// Estimate reflowable EPUB pages at 275 words per page. The page-list above
/// wins whenever the publisher provided one.
fn estimated_pages(epub: &rbook::Epub) -> i64 {
    let words = epub
        .spine()
        .iter()
        .filter_map(|entry| entry.manifest_entry())
        .filter_map(|entry| entry.read_str().ok())
        .map(|html| word_count(&html))
        .sum::<usize>();
    ((words + 274) / 275).max(1) as i64
}

/// Count visible-ish words without parsing XHTML into a DOM just for an estimate.
fn word_count(html: &str) -> usize {
    let (mut words, mut in_tag, mut in_entity, mut in_word) = (0, false, false, false);
    for c in html.chars() {
        match c {
            '<' => { in_tag = true; in_word = false; }
            '>' => in_tag = false,
            '&' if !in_tag => { in_entity = true; in_word = false; }
            ';' if in_entity => in_entity = false,
            c if !in_tag && !in_entity && c.is_alphanumeric() => {
                if !in_word { words += 1; in_word = true; }
            }
            _ if !in_tag && !in_entity => in_word = false,
            _ => {}
        }
    }
    words
}

/// True if `s` is shaped like an ISBN-10 or ISBN-13 (hyphens/spaces ignored).
/// ponytail: shape check, not checksum — enough to reject the uuid/urn values
/// that fill most epub `dc:identifier`s. Add a checksum if false matches show up.
fn looks_like_isbn(s: &str) -> bool {
    let d: String = s.chars().filter(|c| !c.is_whitespace() && *c != '-').collect();
    match d.len() {
        13 => d.bytes().all(|b| b.is_ascii_digit()),
        10 => {
            d[..9].bytes().all(|b| b.is_ascii_digit())
                && matches!(d.as_bytes()[9], b'0'..=b'9' | b'X' | b'x')
        }
        _ => false,
    }
}

/// The bare ISBN inside a `dc:identifier` value, if there is one. EPUBs
/// normally write `urn:isbn:9780…`, so matching on the raw string both missed
/// real ISBNs and made two copies of one book that spelled the identifier
/// differently fail to dedup. Store the digits — one canonical form.
fn isbn_from(value: &str) -> Option<String> {
    let trimmed = value.trim();
    let lower = trimmed.to_ascii_lowercase();
    let bare = ["urn:isbn:", "isbn:", "isbn "]
        .iter()
        .find_map(|prefix| lower.starts_with(prefix).then(|| &trimmed[prefix.len()..]))
        .unwrap_or(trimmed);
    let digits: String = bare.chars().filter(|c| !c.is_whitespace() && *c != '-').collect();
    looks_like_isbn(&digits).then(|| digits.to_ascii_uppercase())
}

fn fallback_title(path: &Path) -> String {
    path.file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Untitled")
        .to_string()
}

/// The metadata `write_metadata` writes into an epub. ISBN is omitted because it
/// often supplies the package `unique-identifier`, so rewriting it risks breaking
/// that link. Series uses Calibre's widely supported EPUB metadata convention.
/// Optional fields are `None` when cleared.
pub struct EpubEdit<'a> {
    pub title: &'a str,
    pub authors: &'a [String],
    pub publisher: Option<&'a str>,
    pub language: Option<&'a str>,
    pub description: Option<&'a str>,
    pub series: Option<&'a str>,
    pub series_index: Option<f64>,
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
    // Write the standard EPUB 3 collection vocabulary as the primary form.
    // Keep Calibre's EPUB 2 fields alongside it for compatibility with readers
    // and metadata tools that have not adopted collection refinements.
    editor = editor.clear_meta("belongs-to-collection");
    editor = editor.clear_meta("calibre:series");
    editor = editor.clear_meta("calibre:series_index");
    if let Some(series) = edit.series {
        let mut collection = DetachedEpubMetaEntry::meta("belongs-to-collection")
            .value(series)
            .refinement(DetachedEpubMetaEntry::meta("collection-type").value("series"));
        if let Some(index) = edit.series_index {
            collection = collection.refinement(
                DetachedEpubMetaEntry::meta("group-position").value(index.to_string()),
            );
        }
        editor = editor.meta(collection);
        editor = editor.meta(DetachedEpubMetaEntry::meta_name("calibre:series").value(series));
        if let Some(index) = edit.series_index {
            editor = editor.meta(
                DetachedEpubMetaEntry::meta_name("calibre:series_index").value(index.to_string()),
            );
        }
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

#[cfg(test)]
mod tests {
    use super::{isbn_from, looks_like_isbn, word_count};

    #[test]
    fn isbn_extracted_from_identifier_forms() {
        // The form nearly every epub uses.
        assert_eq!(isbn_from("urn:isbn:9781234567897").as_deref(), Some("9781234567897"));
        // Prefixes and punctuation collapse to one canonical value.
        assert_eq!(isbn_from("ISBN 978-0-307-95154-0").as_deref(), Some("9780307951540"));
        assert_eq!(isbn_from("  080442957x ").as_deref(), Some("080442957X"));
        // Identifiers that aren't ISBNs stay out of the field.
        assert_eq!(isbn_from("urn:uuid:735093b7-c3c4-4d73-8a0f-96f1750d1140"), None);
    }

    #[test]
    fn counts_visible_words() {
        assert_eq!(word_count("<p>Hello <em>world</em>&nbsp;again.</p>"), 3);
    }

    #[test]
    fn isbn_shape() {
        // Real ISBNs (with and without hyphens, ISBN-10 X check digit).
        assert!(looks_like_isbn("978-0-307-95154-0"));
        assert!(looks_like_isbn("9780393711752"));
        assert!(looks_like_isbn("080442957X"));
        // uuid / urn / junk that fills most epub identifiers.
        assert!(!looks_like_isbn("99d7f960-0ff9-47f6-b677-f799aab4ef3a"));
        assert!(!looks_like_isbn("urn:uuid:735093b7-c3c4-4d73-8a0f-96f1750d1140"));
        assert!(!looks_like_isbn(""));
        assert!(!looks_like_isbn("12345"));
    }
}

//! Native EPUB → MOBI6 writer.
//!
//! Clean-room from the MOBI/PDB format (mobileread wiki); the `mobi` crate is
//! our reader/oracle in tests. Byte layouts (PDB 78 B, PalmDOC 16 B, MOBI
//! header 232 B, EXTH) match the standard the `mobi` crate parses.
//!
//! ponytail: MOBI6 only, uncompressed text, cover but no inline images, no TOC
//! index. Produces a readable linear book on any Kindle. AZW3/KF8, PalmDOC
//! compression, and NCX indexes are follow-ups.

use std::collections::HashMap;
use std::path::Path;

const TEXT_RECORD_SIZE: usize = 4096;
const NONE: u32 = 0xFFFF_FFFF;
const MOBI_HEADER_LEN: u32 = 232;

/// Convert an epub file to a MOBI6 file on disk.
pub fn epub_to_mobi(epub_path: &str, out_path: &str) -> Result<(), String> {
    let src = read_epub(Path::new(epub_path))?;
    let bytes = build_mobi(&src);
    std::fs::write(out_path, bytes).map_err(|e| format!("write mobi: {e}"))
}

struct Source {
    title: String,
    author: Option<String>,
    isbn: Option<String>,
    description: Option<String>,
    html: Vec<u8>,
    /// Image records in recindex order (image N is at index N-1).
    images: Vec<Vec<u8>>,
    /// 0-based index into `images` of the cover, for EXTH 201.
    cover_recindex: Option<usize>,
}

fn read_epub(path: &Path) -> Result<Source, String> {
    let meta = crate::epub::parse(path)?;
    let epub = rbook::Epub::open(path).map_err(|e| format!("open epub: {e}"))?;

    // Collect every image once, keyed by filename → 1-based recindex, so the
    // MOBI's `<img recindex>` can point at the right record.
    // ponytail: match by basename; epubs with same-named images in different
    // folders would collide (rare) — resolve full relative paths if it bites.
    let mut images: Vec<Vec<u8>> = Vec::new();
    let mut recindex: HashMap<String, usize> = HashMap::new();
    for entry in epub.manifest().images() {
        let href = entry
            .resource()
            .key()
            .value()
            .map(str::to_string)
            .unwrap_or_default();
        let Ok(bytes) = entry.read_bytes() else { continue };
        recindex.entry(basename(&href).to_string()).or_insert(images.len() + 1);
        images.push(optimize_image(bytes));
    }

    // The cover's position among the images (for EXTH 201).
    let cover_recindex = epub
        .manifest()
        .cover_image()
        .and_then(|c| c.resource().key().value().map(basename).map(str::to_string))
        .and_then(|b| recindex.get(&b).copied())
        .map(|rec| rec - 1);

    // Flatten the spine into one HTML stream, rewriting <img src> → recindex and
    // internal <a href> → MOBI filepos (byte offset into the text). We track the
    // byte offset of every id anchor and doc start, emit fixed-width filepos
    // placeholders (so offsets stay stable), then patch in the resolved values.
    const PREFIX: &str = "<html><head></head><body>";
    const SUFFIX: &str = "</body></html>";
    const PAGEBREAK: &str = "<mbp:pagebreak/>";

    let mut body = String::new();
    let mut doc_start: HashMap<String, usize> = HashMap::new();
    let mut id_at: HashMap<(String, String), usize> = HashMap::new();
    let mut links: Vec<Link> = Vec::new();

    let mut first = true;
    let mut reader = epub.reader();
    while let Some(next) = reader.read_next() {
        let data = next.map_err(|e| format!("read spine: {e}"))?;
        let href = basename(data.manifest_entry().resource().key().value().unwrap_or_default())
            .to_string();
        let inner = rewrite_images(body_inner(data.content()), &recindex);

        if !first {
            body.push_str(PAGEBREAK);
        }
        first = false;

        // Byte offset where this document's content begins in the final html.
        let base_off = PREFIX.len() + body.len();
        doc_start.entry(href.clone()).or_insert(base_off);

        let (rewritten, mut doc_links, doc_ids) = rewrite_links(&inner, &href);
        for l in &mut doc_links {
            l.digit_pos += base_off;
        }
        links.extend(doc_links);
        for (id, pos) in doc_ids {
            id_at.entry((href.clone(), id)).or_insert(base_off + pos);
        }
        body.push_str(&rewritten);
    }

    let mut html = format!("{PREFIX}{body}{SUFFIX}").into_bytes();

    // Resolve each internal link to its target byte offset (id anchor if the
    // link had a #fragment, else the document start) and patch the placeholder.
    for link in &links {
        let offset = link
            .frag
            .as_ref()
            .and_then(|f| id_at.get(&(link.target.clone(), f.clone())).copied())
            .or_else(|| doc_start.get(&link.target).copied())
            .unwrap_or(0);
        write_filepos(&mut html, link.digit_pos, offset);
    }

    Ok(Source {
        author: meta.authors.first().cloned(),
        isbn: meta.isbn,
        description: meta.description,
        title: meta.title,
        html,
        images,
        cover_recindex,
    })
}

/// A rewritten internal link awaiting its resolved filepos.
struct Link {
    /// Byte offset in the final html where the filepos digits go.
    digit_pos: usize,
    /// Basename of the target document.
    target: String,
    /// Fragment id, if the link had one.
    frag: Option<String>,
}

const FILEPOS_WIDTH: usize = 10;

/// Overwrite the fixed-width filepos placeholder at `pos` with `offset`.
fn write_filepos(buf: &mut [u8], pos: usize, offset: usize) {
    let s = format!("{offset:0FILEPOS_WIDTH$}");
    let s = &s.as_bytes()[s.len().saturating_sub(FILEPOS_WIDTH)..];
    buf[pos..pos + FILEPOS_WIDTH].copy_from_slice(s);
}

/// Rewrite internal `<a href>` to `<a filepos="0000000000">` (placeholder, later
/// patched), and record the byte offset of every id/name anchor. Returns the
/// rewritten html, the links (offsets local to the returned string), and the
/// anchors as (id, local offset of the enclosing tag).
fn rewrite_links(inner: &str, base: &str) -> (String, Vec<Link>, Vec<(String, usize)>) {
    let mut out = String::with_capacity(inner.len() + 64);
    let mut links = Vec::new();
    let mut ids = Vec::new();
    let bytes = inner.as_bytes();
    let mut i = 0;

    while i < inner.len() {
        if bytes[i] != b'<' {
            let next = inner[i..].find('<').map_or(inner.len(), |e| i + e);
            out.push_str(&inner[i..next]);
            i = next;
            continue;
        }

        let end = inner[i..].find('>').map_or(inner.len(), |e| i + e + 1);
        let tag = &inner[i..end];
        let tag_out_pos = out.len();

        if let Some(id) = attr_value(tag, "id").or_else(|| attr_value(tag, "name")) {
            ids.push((id.to_string(), tag_out_pos));
        }

        if let Some((hpos, value, hlen)) = find_href(tag) {
            if let Some((target, frag)) = internal_target(value, base) {
                out.push_str(&tag[..hpos]);
                let digit_pos = out.len() + "filepos=\"".len();
                out.push_str("filepos=\"0000000000\"");
                out.push_str(&tag[hpos + hlen..]);
                links.push(Link { digit_pos, target, frag });
                i = end;
                continue;
            }
        }

        out.push_str(tag);
        i = end;
    }

    (out, links, ids)
}

/// Resolve an href to (target basename, fragment). Returns None for external
/// links (http/mailto/etc.), which are left untouched.
fn internal_target(href: &str, base: &str) -> Option<(String, Option<String>)> {
    let href = href.trim();
    if href.is_empty() || href.contains("://") || href.starts_with("mailto:")
        || href.starts_with("tel:") || href.starts_with("//")
    {
        return None;
    }
    let (path, frag) = match href.split_once('#') {
        Some((p, f)) => (p, Some(f.to_string())),
        None => (href, None),
    };
    let target = if path.is_empty() { base.to_string() } else { basename(path).to_string() };
    Some((target, frag))
}

/// Value of `name="..."`/`name='...'` in a tag, matched only at an attribute
/// boundary (preceded by whitespace) so it never matches inside another word.
fn attr_value<'a>(tag: &'a str, name: &str) -> Option<&'a str> {
    let bytes = tag.as_bytes();
    let mut search = 0;
    while let Some(rel) = tag[search..].find(name) {
        let at = search + rel;
        let before = if at == 0 { b'<' } else { bytes[at - 1] };
        let after = at + name.len();
        if matches!(before, b' ' | b'\t' | b'\n' | b'\r') && bytes.get(after) == Some(&b'=') {
            if let Some(&q) = bytes.get(after + 1) {
                if q == b'"' || q == b'\'' {
                    let vs = after + 2;
                    if let Some(e) = tag[vs..].find(q as char) {
                        return Some(&tag[vs..vs + e]);
                    }
                }
            }
        }
        search = at + name.len();
    }
    None
}

/// Locate an `href` attribute, returning (byte pos of "href", value, full length
/// of the `href="value"` span).
fn find_href(tag: &str) -> Option<(usize, &str, usize)> {
    let bytes = tag.as_bytes();
    let mut search = 0;
    while let Some(rel) = tag[search..].find("href") {
        let at = search + rel;
        let before = if at == 0 { b'<' } else { bytes[at - 1] };
        let after = at + 4;
        if matches!(before, b' ' | b'\t' | b'\n' | b'\r') && bytes.get(after) == Some(&b'=') {
            if let Some(&q) = bytes.get(after + 1) {
                if q == b'"' || q == b'\'' {
                    let vs = after + 2;
                    if let Some(e) = tag[vs..].find(q as char) {
                        return Some((at, &tag[vs..vs + e], (vs + e + 1) - at));
                    }
                }
            }
        }
        search = at + 4;
    }
    None
}

/// Keep each embedded image under the MOBI comfort limit, which large images
/// blow past — the Kindle renders those pages slowly. Oversized images are
/// downscaled and JPEG-recompressed (like Calibre); small ones pass through
/// untouched so sharp line-art/diagrams keep their original format.
///
/// ponytail: quality ladder at ≤1600px nearly always lands under the cap; add a
/// second downscale pass only if a pathological image slips through.
fn optimize_image(bytes: Vec<u8>) -> Vec<u8> {
    const MAX_BYTES: usize = 120_000; // stay under the ~127 KB MOBI image limit
    const MAX_DIM: u32 = 1600;

    if bytes.len() <= MAX_BYTES {
        return bytes;
    }
    let Ok(mut img) = image::load_from_memory(&bytes) else {
        return bytes; // undecodable — ship as-is rather than drop it
    };
    if img.width() > MAX_DIM || img.height() > MAX_DIM {
        img = img.resize(MAX_DIM, MAX_DIM, image::imageops::FilterType::Lanczos3);
    }
    let rgb = img.to_rgb8();

    let mut best = bytes;
    for quality in [82u8, 70, 60, 50, 40] {
        let mut buf = Vec::new();
        use image::{ExtendedColorType, ImageEncoder};
        let enc = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut buf, quality);
        if enc
            .write_image(rgb.as_raw(), rgb.width(), rgb.height(), ExtendedColorType::Rgb8)
            .is_err()
        {
            break;
        }
        if buf.len() < best.len() {
            best = buf.clone();
        }
        if buf.len() <= MAX_BYTES {
            return buf;
        }
    }
    best
}

/// Last path component of a resource href.
fn basename(href: &str) -> &str {
    href.rsplit(['/', '\\']).next().unwrap_or(href)
}

/// Rewrite each `<img src="…">` to `<img recindex="000NN">` using the image's
/// filename. Unmatched images keep their src (harmless — MOBI ignores it).
fn rewrite_images(html: &str, recindex: &HashMap<String, usize>) -> String {
    let mut out = String::with_capacity(html.len());
    let mut rest = html;
    while let Some(pos) = rest.find("src=") {
        out.push_str(&rest[..pos]);
        let after = &rest[pos + 4..];
        let quote = after.as_bytes().first().copied();
        if quote == Some(b'"') || quote == Some(b'\'') {
            let q = quote.unwrap() as char;
            if let Some(end) = after[1..].find(q) {
                let value = &after[1..1 + end];
                if let Some(&rec) = recindex.get(basename(value)) {
                    out.push_str(&format!("recindex=\"{rec:05}\""));
                } else {
                    out.push_str(&rest[pos..pos + 4 + 2 + end]); // keep src="value"
                }
                rest = &after[1 + end + 1..];
                continue;
            }
        }
        // Not a normal src attribute — emit "src=" verbatim and move on.
        out.push_str("src=");
        rest = after;
    }
    out.push_str(rest);
    out
}

/// Inner HTML of the first `<body>…</body>`, else the whole document.
fn body_inner(html: &str) -> &str {
    let start = html
        .find("<body")
        .and_then(|i| html[i..].find('>').map(|j| i + j + 1));
    let end = html.rfind("</body>");
    match (start, end) {
        (Some(s), Some(e)) if s <= e => &html[s..e],
        _ => html,
    }
}

fn build_mobi(src: &Source) -> Vec<u8> {
    // text_len is the *uncompressed* total; records are PalmDOC-compressed
    // independently (matches must not cross the 4096-byte record boundary).
    let text_len = src.html.len() as u32;
    let text_records: Vec<Vec<u8>> = if src.html.is_empty() {
        vec![Vec::new()]
    } else {
        src.html.chunks(TEXT_RECORD_SIZE).map(palmdoc_compress).collect()
    };
    let n_text = text_records.len();

    // Record numbering: 0 = header, 1..=n_text = text, then images, FLIS, FCIS, EOF.
    let last_text = n_text; // 1-based record index of the last text record
    let n_images = src.images.len();
    let first_image_record = last_text + 1; // record index of image #1 (recindex 1)
    let flis_index = last_text + n_images + 1;
    let fcis_index = flis_index + 1;

    let record0 = build_record0(
        src,
        text_len,
        n_text,
        /* first_image_index */ if n_images > 0 { first_image_record as u32 } else { NONE },
        /* first_non_book_index */ (last_text + 1) as u32,
        /* last_content_record */ (flis_index - 1) as u16,
        fcis_index as u32,
        flis_index as u32,
    );

    let mut records: Vec<Vec<u8>> = Vec::with_capacity(n_text + n_images + 4);
    records.push(record0);
    records.extend(text_records);
    records.extend(src.images.iter().cloned());
    records.push(flis_record());
    records.push(fcis_record(text_len));
    records.push(vec![0xE9, 0x8E, 0x0D, 0x0A]); // EOF record

    write_pdb(&src.title, &records)
}

fn build_record0(
    src: &Source,
    text_len: u32,
    n_text: usize,
    first_image_index: u32,
    first_non_book_index: u32,
    last_content_record: u16,
    fcis_record: u32,
    flis_record: u32,
) -> Vec<u8> {
    let exth = build_exth(src);
    let name = src.title.as_bytes();
    let name_offset = 16 + MOBI_HEADER_LEN as usize + exth.len();

    let mut rec = Vec::new();
    rec.extend_from_slice(&palmdoc_header(text_len, n_text));
    rec.extend_from_slice(&mobi_header(
        name_offset as u32,
        name.len() as u32,
        first_image_index,
        first_non_book_index,
        last_content_record,
        fcis_record,
        flis_record,
    ));
    rec.extend_from_slice(&exth);
    rec.extend_from_slice(name);
    // Pad to a 4-byte boundary, plus a little trailing slack (writers do this).
    while rec.len() % 4 != 0 {
        rec.push(0);
    }
    rec.extend_from_slice(&[0, 0]);
    rec
}

fn palmdoc_header(text_len: u32, n_text: usize) -> [u8; 16] {
    let mut h = [0u8; 16];
    h[0..2].copy_from_slice(&2u16.to_be_bytes()); // compression: PalmDOC
    // 2..4 unused
    h[4..8].copy_from_slice(&text_len.to_be_bytes());
    h[8..10].copy_from_slice(&(n_text as u16).to_be_bytes());
    h[10..12].copy_from_slice(&(TEXT_RECORD_SIZE as u16).to_be_bytes());
    // 12..14 encryption: none, 14..16 unused
    h
}

/// The 232-byte MOBI header, fields in the exact order the `mobi` crate parses.
fn mobi_header(
    name_offset: u32,
    name_length: u32,
    first_image_index: u32,
    first_non_book_index: u32,
    last_content_record: u16,
    fcis_record: u32,
    flis_record: u32,
) -> Vec<u8> {
    let mut h = Vec::with_capacity(MOBI_HEADER_LEN as usize);
    let u32 = |h: &mut Vec<u8>, v: u32| h.extend_from_slice(&v.to_be_bytes());
    let u16 = |h: &mut Vec<u8>, v: u16| h.extend_from_slice(&v.to_be_bytes());

    h.extend_from_slice(b"MOBI"); // identifier
    u32(&mut h, MOBI_HEADER_LEN); // header_length
    u32(&mut h, 2); // mobi_type: book
    u32(&mut h, 65001); // text_encoding: UTF-8
    u32(&mut h, 0); // id
    u32(&mut h, 6); // gen_version
    u32(&mut h, NONE); // ortho_index
    u32(&mut h, NONE); // inflect_index
    u32(&mut h, NONE); // index_names
    u32(&mut h, NONE); // index_keys
    for _ in 0..6 {
        u32(&mut h, NONE); // extra_indices
    }
    u32(&mut h, first_non_book_index);
    u32(&mut h, name_offset);
    u32(&mut h, name_length);
    u16(&mut h, 0); // unused
    h.push(0); // locale
    h.push(0); // language_code: Neutral
    u32(&mut h, 0); // input_language
    u32(&mut h, 0); // output_language
    u32(&mut h, 6); // format_version
    u32(&mut h, first_image_index);
    u32(&mut h, 0); // first_huff_record
    u32(&mut h, 0); // huff_record_count
    u32(&mut h, 0); // huff_table_offset
    u32(&mut h, 0); // huff_table_length
    u32(&mut h, 0x40); // exth_flags: EXTH present
    h.extend_from_slice(&[0u8; 32]); // unused_0
    u32(&mut h, NONE); // unused_1
    u32(&mut h, NONE); // drm_offset: no DRM
    u32(&mut h, 0); // drm_count
    u32(&mut h, 0); // drm_size
    u32(&mut h, 0); // drm_flags
    h.extend_from_slice(&[0u8; 8]); // unused_2
    u16(&mut h, 1); // first_content_record
    u16(&mut h, last_content_record);
    u32(&mut h, 0); // unused_3
    u32(&mut h, fcis_record);
    u32(&mut h, 1); // fcis count
    u32(&mut h, flis_record);
    u32(&mut h, 1); // flis count
    u32(&mut h, 0); // unused_6 (u64 hi)
    u32(&mut h, 0); // unused_6 (u64 lo)
    u32(&mut h, 0); // unused_7
    u32(&mut h, 0); // first_compilation_data_section_count
    u32(&mut h, 0); // data_section_count
    u32(&mut h, 0); // unused_8
    u32(&mut h, 0); // extra_record_data_flags: no trailing bytes on text records
    u32(&mut h, NONE); // first_index_record

    debug_assert_eq!(h.len(), MOBI_HEADER_LEN as usize);
    h
}

fn build_exth(src: &Source) -> Vec<u8> {
    let mut recs: Vec<(u32, Vec<u8>)> = Vec::new();
    if let Some(a) = &src.author {
        recs.push((100, a.clone().into_bytes()));
    }
    if let Some(d) = &src.description {
        recs.push((103, d.clone().into_bytes()));
    }
    if let Some(i) = &src.isbn {
        recs.push((104, i.clone().into_bytes()));
    }
    if let Some(cover) = src.cover_recindex {
        recs.push((201, (cover as u32).to_be_bytes().to_vec())); // cover image offset
        recs.push((202, (cover as u32).to_be_bytes().to_vec())); // thumbnail offset
    }

    let mut body = Vec::new();
    for (ty, data) in &recs {
        body.extend_from_slice(&ty.to_be_bytes());
        body.extend_from_slice(&((8 + data.len()) as u32).to_be_bytes());
        body.extend_from_slice(data);
    }

    let unpadded = 12 + body.len();
    let pad = (4 - unpadded % 4) % 4;

    let mut out = Vec::with_capacity(unpadded + pad);
    out.extend_from_slice(b"EXTH");
    out.extend_from_slice(&((unpadded + pad) as u32).to_be_bytes());
    out.extend_from_slice(&(recs.len() as u32).to_be_bytes());
    out.extend_from_slice(&body);
    out.resize(unpadded + pad, 0);
    out
}

/// FLIS record — fixed structure marking end of the book's flow.
fn flis_record() -> Vec<u8> {
    let mut r = b"FLIS".to_vec();
    r.extend_from_slice(&8u32.to_be_bytes());
    r.extend_from_slice(&65u16.to_be_bytes());
    r.extend_from_slice(&0u16.to_be_bytes());
    r.extend_from_slice(&0u32.to_be_bytes());
    r.extend_from_slice(&NONE.to_be_bytes());
    r.extend_from_slice(&1u16.to_be_bytes());
    r.extend_from_slice(&3u16.to_be_bytes());
    r.extend_from_slice(&3u32.to_be_bytes());
    r.extend_from_slice(&1u32.to_be_bytes());
    r.extend_from_slice(&NONE.to_be_bytes());
    r
}

/// FCIS record — fixed structure carrying the text length.
fn fcis_record(text_len: u32) -> Vec<u8> {
    let mut r = b"FCIS".to_vec();
    r.extend_from_slice(&20u32.to_be_bytes());
    r.extend_from_slice(&16u32.to_be_bytes());
    r.extend_from_slice(&1u32.to_be_bytes());
    r.extend_from_slice(&0u32.to_be_bytes());
    r.extend_from_slice(&text_len.to_be_bytes());
    r.extend_from_slice(&0u32.to_be_bytes());
    r.extend_from_slice(&32u32.to_be_bytes());
    r.extend_from_slice(&8u32.to_be_bytes());
    r.extend_from_slice(&1u16.to_be_bytes());
    r.extend_from_slice(&1u16.to_be_bytes());
    r.extend_from_slice(&0u32.to_be_bytes());
    r
}

/// Write the Palm Database container: 78-byte header, record-offset table,
/// 2-byte gap, then records.
fn write_pdb(title: &str, records: &[Vec<u8>]) -> Vec<u8> {
    let n = records.len();
    let data_start = 78 + n * 8 + 2;

    let mut out = Vec::new();
    // name: 32 bytes, null-padded
    let mut name = [0u8; 32];
    let tb = title.as_bytes();
    let len = tb.len().min(31);
    name[..len].copy_from_slice(&tb[..len]);
    out.extend_from_slice(&name);

    out.extend_from_slice(&0u16.to_be_bytes()); // attributes
    out.extend_from_slice(&0u16.to_be_bytes()); // version
    out.extend_from_slice(&0u32.to_be_bytes()); // created
    out.extend_from_slice(&0u32.to_be_bytes()); // modified
    out.extend_from_slice(&0u32.to_be_bytes()); // backup
    out.extend_from_slice(&0u32.to_be_bytes()); // modnum
    out.extend_from_slice(&0u32.to_be_bytes()); // app_info_id
    out.extend_from_slice(&0u32.to_be_bytes()); // sort_info_id
    out.extend_from_slice(b"BOOK"); // type
    out.extend_from_slice(b"MOBI"); // creator
    out.extend_from_slice(&((n * 2) as u32).to_be_bytes()); // unique_id_seed
    out.extend_from_slice(&0u32.to_be_bytes()); // next_record_list_id
    out.extend_from_slice(&(n as u16).to_be_bytes()); // num_records

    let mut offset = data_start;
    for (i, rec) in records.iter().enumerate() {
        out.extend_from_slice(&(offset as u32).to_be_bytes());
        let uid = (i * 2) as u32;
        out.push(0); // attributes
        out.push((uid >> 16) as u8);
        out.push((uid >> 8) as u8);
        out.push(uid as u8);
        offset += rec.len();
    }
    out.extend_from_slice(&[0, 0]); // gap to first record

    for rec in records {
        out.extend_from_slice(rec);
    }
    out
}

// ---------------------------------------------------------------------------
// PalmDOC (LZ77) compression — MOBI compression type 2.
//
// Byte codes on the compressed stream:
//   0x00        literal NUL
//   0x01..=0x08 escape: the next N bytes are literal
//   0x09..=0x7F literal ASCII byte
//   0x80..=0xBF 2-byte back-reference: 10 dddddddddd dll  (dist 1..2047, len 3..10)
//   0xC0..=0xFF space + (byte ^ 0x80)   — the "space char" optimization
// ---------------------------------------------------------------------------

/// Compress a byte slice with PalmDOC LZ77.
///
/// ponytail: 3-byte hash chain, depth-capped at 64 — good ratio, bounded time.
/// A full match search would compress a hair smaller for far more CPU.
fn palmdoc_compress(data: &[u8]) -> Vec<u8> {
    use std::collections::HashMap;
    const MAX_LEN: usize = 10;
    const MAX_DIST: usize = 2047;
    const MAX_CHAIN: usize = 64;

    let n = data.len();
    let mut out = Vec::with_capacity(n / 2 + 16);
    let mut head: HashMap<[u8; 3], usize> = HashMap::new();
    let mut prev = vec![usize::MAX; n.max(1)];

    let mut i = 0;
    while i < n {
        let mut best_len = 0usize;
        let mut best_dist = 0usize;

        if i + 2 < n {
            let key = [data[i], data[i + 1], data[i + 2]];
            let max_len = MAX_LEN.min(n - i);
            let min_pos = i.saturating_sub(MAX_DIST);

            let mut cand = head.get(&key).copied().unwrap_or(usize::MAX);
            let mut chain = 0;
            while cand != usize::MAX && cand >= min_pos && chain < MAX_CHAIN {
                let mut l = 0;
                while l < max_len && data[cand + l] == data[i + l] {
                    l += 1;
                }
                if l > best_len {
                    best_len = l;
                    best_dist = i - cand;
                    if l == max_len {
                        break;
                    }
                }
                cand = prev[cand];
                chain += 1;
            }

            // Index the current position for future matches.
            prev[i] = head.get(&key).copied().unwrap_or(usize::MAX);
            head.insert(key, i);
        }

        if best_len >= 3 {
            let val = 0x8000u16 | ((best_dist as u16) << 3) | ((best_len - 3) as u16);
            out.push((val >> 8) as u8);
            out.push(val as u8);
            i += best_len;
            continue;
        }

        let c = data[i];
        if c == 0x20 && i + 1 < n && (0x40..=0x7F).contains(&data[i + 1]) {
            out.push(data[i + 1] ^ 0x80);
            i += 2;
        } else if c == 0x00 || (0x09..=0x7F).contains(&c) {
            out.push(c);
            i += 1;
        } else {
            // Escape run: 1..8 bytes that can't be emitted directly.
            let start = i;
            let mut count = 0;
            while count < 8 && i < n {
                let b = data[i];
                if b == 0x00 || (0x09..=0x7F).contains(&b) {
                    break;
                }
                count += 1;
                i += 1;
            }
            out.push(count as u8);
            out.extend_from_slice(&data[start..start + count]);
        }
    }
    out
}

/// Decompress a PalmDOC LZ77 stream. Public so tests (and future readers) can
/// verify our output round-trips.
pub fn palmdoc_decompress(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(data.len() * 2);
    let n = data.len();
    let mut i = 0;
    while i < n {
        let b = data[i];
        i += 1;
        match b {
            0x00 => out.push(0x00),
            0x01..=0x08 => {
                for _ in 0..b as usize {
                    if i < n {
                        out.push(data[i]);
                        i += 1;
                    }
                }
            }
            0x09..=0x7F => out.push(b),
            0x80..=0xBF => {
                if i >= n {
                    break;
                }
                let val = ((b as u16) << 8) | data[i] as u16;
                i += 1;
                let dist = ((val >> 3) & 0x07FF) as usize;
                let len = ((val & 0x07) + 3) as usize;
                if dist == 0 || dist > out.len() {
                    break;
                }
                let mut pos = out.len() - dist;
                for _ in 0..len {
                    let byte = out[pos];
                    out.push(byte);
                    pos += 1;
                }
            }
            0xC0..=0xFF => {
                out.push(0x20);
                out.push(b ^ 0x80);
            }
        }
    }
    out
}

#[cfg(test)]
mod palmdoc_tests {
    use super::{palmdoc_compress, palmdoc_decompress};

    fn roundtrip(data: &[u8]) {
        let c = palmdoc_compress(data);
        assert_eq!(palmdoc_decompress(&c), data, "roundtrip failed for {data:?}");
    }

    #[test]
    fn roundtrips_and_compresses() {
        roundtrip(b"");
        roundtrip(b"a");
        roundtrip(b"aaaaaaaaaaaaaaaaaaaa"); // runs -> back-references
        roundtrip(b"the quick brown fox jumps over the quick brown fox");
        roundtrip("accented: café — naïve “quotes”".as_bytes()); // multibyte escapes
        roundtrip(&(0u8..=255).cycle().take(5000).collect::<Vec<_>>());

        // A repetitive HTML-ish blob must actually shrink.
        let html = "<p>Hello world.</p>".repeat(500);
        let c = palmdoc_compress(html.as_bytes());
        assert!(c.len() < html.len() / 2, "expected >2x compression");
        assert_eq!(palmdoc_decompress(&c), html.as_bytes());
    }
}

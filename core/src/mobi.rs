//! Native EPUB → MOBI6 writer.
//!
//! Clean-room from the MOBI/PDB format (mobileread wiki); the `mobi` crate is
//! our reader/oracle in tests. Byte layouts (PDB 78 B, PalmDOC 16 B, MOBI
//! header 232 B, EXTH) match the standard the `mobi` crate parses.
//!
//! ponytail: MOBI6 only, uncompressed text, cover but no inline images, no TOC
//! index. Produces a readable linear book on any Kindle. AZW3/KF8, PalmDOC
//! compression, and NCX indexes are follow-ups.

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
    cover: Option<Vec<u8>>,
}

fn read_epub(path: &Path) -> Result<Source, String> {
    let meta = crate::epub::parse(path)?;
    let epub = rbook::Epub::open(path).map_err(|e| format!("open epub: {e}"))?;

    // Flatten the spine into one HTML stream, page-break between documents.
    let mut body = String::new();
    let mut first = true;
    let mut reader = epub.reader();
    while let Some(next) = reader.read_next() {
        let data = next.map_err(|e| format!("read spine: {e}"))?;
        let content = data.content();
        if !first {
            body.push_str("<mbp:pagebreak/>");
        }
        first = false;
        body.push_str(body_inner(content.as_ref()));
    }
    let html = format!("<html><head></head><body>{body}</body></html>");

    Ok(Source {
        author: meta.authors.first().cloned(),
        isbn: meta.isbn,
        description: meta.description,
        title: meta.title,
        html: html.into_bytes(),
        cover: meta.cover,
    })
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
    let text_len = src.html.len() as u32;
    let text_records: Vec<Vec<u8>> = if src.html.is_empty() {
        vec![Vec::new()]
    } else {
        src.html.chunks(TEXT_RECORD_SIZE).map(<[u8]>::to_vec).collect()
    };
    let n_text = text_records.len();

    // Record numbering: 0 = header, 1..=n_text = text, then cover, FLIS, FCIS, EOF.
    let last_text = n_text; // 1-based record index of the last text record
    let has_cover = src.cover.is_some();
    let first_image_record = if has_cover { last_text + 1 } else { 0 };
    let flis_index = last_text + if has_cover { 1 } else { 0 } + 1;
    let fcis_index = flis_index + 1;

    let record0 = build_record0(
        src,
        text_len,
        n_text,
        /* first_image_index */ if has_cover { first_image_record as u32 } else { NONE },
        /* first_non_book_index */ (last_text + 1) as u32,
        /* last_content_record */ last_text as u16,
        fcis_index as u32,
        flis_index as u32,
    );

    let mut records: Vec<Vec<u8>> = Vec::with_capacity(n_text + 4);
    records.push(record0);
    records.extend(text_records);
    if let Some(cover) = &src.cover {
        records.push(cover.clone());
    }
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
    h[0..2].copy_from_slice(&1u16.to_be_bytes()); // compression: none
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
    if src.cover.is_some() {
        recs.push((201, 0u32.to_be_bytes().to_vec())); // cover offset (image index 0)
        recs.push((202, 0u32.to_be_bytes().to_vec())); // thumbnail offset
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
    out.extend_from_slice(&(n as u32).to_be_bytes()); // unique_id_seed
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

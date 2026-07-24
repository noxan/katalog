//! MOBI6 NCX table-of-contents index (INDX / TAGX / IDXT / CNCX records).
//!
//! Drives the Kindle's hardware "Go To → Table of Contents" menu and chapter
//! location marks. Clean-room: every byte layout below was decoded from a
//! Calibre-produced .mobi (field-by-field, varints verified against real
//! entries), not copied from GPL source.
//!
//! ponytail: FLAT TOC only — the epub's nav tree is walked in reading order and
//! emitted as a single-level list (tags offset/length/label/depth, depth always
//! 0). Nested TOC (parent/child tags 21–23) is a later addition. If the entries
//! or labels don't fit one 64 KB record, we return None and the book ships with
//! no index (exactly today's behavior) rather than risk a corrupt one.

/// A resolved TOC entry: its label and the byte offset it points at in the text.
pub struct TocEntry {
    pub label: String,
    pub offset: u32,
}

/// The three records that make up the index, in order.
pub struct Index {
    pub header: Vec<u8>,
    pub entries: Vec<u8>,
    pub cncx: Vec<u8>,
}

const INDX_HEADER_LEN: u32 = 0xC0; // 192 — where TAGX (header rec) / entries begin

/// MOBI variable-width integer: base-128, most-significant group first, with the
/// terminator bit (0x80) set on the LAST byte. (Verified: 3643 → `1c bb`.)
fn vwi(mut n: u32) -> Vec<u8> {
    let mut out = vec![(n & 0x7f) as u8];
    n >>= 7;
    while n > 0 {
        out.push((n & 0x7f) as u8);
        n >>= 7;
    }
    out.reverse();
    let last = out.len() - 1;
    out[last] |= 0x80;
    out
}

/// The 192-byte INDX record header, zero-padded after the 13 longwords.
fn indx_header(type_: u32, gen: u32, idxt_start: u32, count: u32, code: u32, total: u32, nctoc: u32) -> Vec<u8> {
    let mut h = Vec::with_capacity(INDX_HEADER_LEN as usize);
    h.extend_from_slice(b"INDX");
    for v in [
        INDX_HEADER_LEN, // len
        0,               // nul1
        type_,           // type: 0 = index-header record, 1 = entry record
        gen,             // gen
        idxt_start,      // IDXT offset within this record
        count,           // entries in this record (header rec: 1)
        code,            // encoding: 65001 header rec, 0xFFFFFFFF entry rec
        0xFFFF_FFFF,     // lng
        total,           // total entries across entry records (header rec only)
        0,               // ordt
        0,               // ligt
        0,               // nligt
        nctoc,           // CNCX record count (header rec: 1)
    ] {
        h.extend_from_slice(&v.to_be_bytes());
    }
    h.resize(INDX_HEADER_LEN as usize, 0);
    h
}

/// Fixed TAGX table for a flat NCX: tags offset(1)/length(2)/label(3)/depth(4).
fn tagx() -> Vec<u8> {
    let mut t = Vec::new();
    t.extend_from_slice(b"TAGX");
    t.extend_from_slice(&32u32.to_be_bytes()); // length (12 + 5*4)
    t.extend_from_slice(&1u32.to_be_bytes()); // control byte count
    for (tag, nvals, mask, end) in [(1, 1, 0x01, 0), (2, 1, 0x02, 0), (3, 1, 0x04, 0), (4, 1, 0x08, 0), (0, 0, 0, 1)] {
        t.extend_from_slice(&[tag, nvals, mask, end]);
    }
    t
}

/// Build the NCX index for `toc`. `text_len` bounds the last entry's length.
/// Returns None if there's nothing to index or it wouldn't fit one record each.
pub fn build_ncx(toc: &[TocEntry], text_len: u32) -> Option<Index> {
    // Sort by target offset (the index must be ascending) and drop duplicates.
    let mut items: Vec<&TocEntry> = toc.iter().filter(|e| e.offset < text_len).collect();
    items.sort_by_key(|e| e.offset);
    items.dedup_by_key(|e| e.offset);
    if items.is_empty() {
        return None;
    }
    let n = items.len();
    if n > 0xFFFF {
        return None; // absurd TOC — fall back to no index
    }

    // CNCX: [vwi(byte-len)][utf8] per label; label offset = its byte position.
    let mut cncx = Vec::new();
    let mut label_off = Vec::with_capacity(n);
    for e in &items {
        label_off.push(cncx.len() as u32);
        let bytes = e.label.as_bytes();
        cncx.extend_from_slice(&vwi(bytes.len() as u32));
        cncx.extend_from_slice(bytes);
    }
    if cncx.len() > 0xFFFF {
        return None;
    }

    // Entry idents: fixed-width uppercase hex of the entry number.
    let mut width = format!("{:X}", n.saturating_sub(1)).len();
    if width % 2 == 1 {
        width += 1;
    }
    width = width.max(2);

    // Entry blocks + their offsets (relative to the entry record start).
    let mut blocks = Vec::new();
    let mut entry_offsets = Vec::with_capacity(n);
    let mut cursor = INDX_HEADER_LEN as usize;
    for (i, e) in items.iter().enumerate() {
        let next = items.get(i + 1).map(|x| x.offset).unwrap_or(text_len);
        let length = next.saturating_sub(e.offset);
        let ident = format!("{:0width$X}", i, width = width);

        let mut blk = Vec::new();
        blk.push(ident.len() as u8);
        blk.extend_from_slice(ident.as_bytes());
        blk.push(0x0F); // control byte: tags 1,2,3,4 present
        blk.extend_from_slice(&vwi(e.offset));
        blk.extend_from_slice(&vwi(length));
        blk.extend_from_slice(&vwi(label_off[i]));
        blk.extend_from_slice(&vwi(0)); // depth
        entry_offsets.push(cursor as u16);
        cursor += blk.len();
        blocks.extend_from_slice(&blk);
    }
    if cursor + 4 + n * 2 > 0xFFFF {
        return None; // entries + IDXT don't fit one record
    }

    // Entry record: header(type=1) + blocks + IDXT.
    let idxt_start = INDX_HEADER_LEN as usize + blocks.len();
    let mut entries = indx_header(1, 0, idxt_start as u32, n as u32, 0xFFFF_FFFF, 0, 0);
    entries.extend_from_slice(&blocks);
    entries.extend_from_slice(b"IDXT");
    for off in &entry_offsets {
        entries.extend_from_slice(&off.to_be_bytes());
    }
    pad4(&mut entries);

    // Index-header record: header(type=0) + TAGX + geometry entry + IDXT.
    let mut header = indx_header(0, 2, 0, 1, 65001, n as u32, 1);
    header.extend_from_slice(&tagx());
    let geom_off = header.len() as u16; // = 224 (0xC0 + 0x20)
    let last_ident = format!("{:0width$X}", n - 1, width = width);
    header.push(last_ident.len() as u8);
    header.extend_from_slice(last_ident.as_bytes());
    // Geometry tail as Calibre emits it: 0x00, entry-count byte, 0x00 0x00 0x00.
    header.extend_from_slice(&[0x00, n as u8, 0x00, 0x00, 0x00]);
    let hdr_idxt = header.len() as u32;
    header.extend_from_slice(b"IDXT");
    header.extend_from_slice(&geom_off.to_be_bytes());
    pad4(&mut header);
    // Patch the header's IDXT-start field (offset 0x14) now that we know it.
    header[0x14..0x18].copy_from_slice(&hdr_idxt.to_be_bytes());

    Some(Index { header, entries, cncx })
}

fn pad4(v: &mut Vec<u8>) {
    while v.len() % 4 != 0 {
        v.push(0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vwi_matches_known_values() {
        assert_eq!(vwi(0), vec![0x80]);
        assert_eq!(vwi(0x7f), vec![0xff]);
        assert_eq!(vwi(0x80), vec![0x01, 0x80]);
        assert_eq!(vwi(3643), vec![0x1c, 0xbb]); // real Calibre entry offset
        assert_eq!(vwi(134), vec![0x01, 0x86]); // real Calibre entry length
    }

    #[test]
    fn tagx_bytes_match_calibre() {
        assert_eq!(
            tagx(),
            vec![
                b'T', b'A', b'G', b'X', 0, 0, 0, 32, 0, 0, 0, 1, //
                1, 1, 1, 0, 2, 1, 2, 0, 3, 1, 4, 0, 4, 1, 8, 0, 0, 0, 0, 1,
            ]
        );
    }

    #[test]
    fn builds_a_flat_index_that_round_trips() {
        let toc = vec![
            TocEntry { label: "Title Page".into(), offset: 3643 },
            TocEntry { label: "Copyright".into(), offset: 3777 },
            TocEntry { label: "Chapter One".into(), offset: 5718 },
        ];
        let idx = build_ncx(&toc, 10_000).expect("index built");

        // Header record: magic, len, type 0, count 1, code 65001, total 3, nctoc 1.
        assert_eq!(&idx.header[0..4], b"INDX");
        assert_eq!(u32::from_be_bytes(idx.header[0x0C..0x10].try_into().unwrap()), 0);
        assert_eq!(u32::from_be_bytes(idx.header[0x18..0x1C].try_into().unwrap()), 1);
        assert_eq!(u32::from_be_bytes(idx.header[0x1C..0x20].try_into().unwrap()), 65001);
        assert_eq!(u32::from_be_bytes(idx.header[0x24..0x28].try_into().unwrap()), 3);
        assert_eq!(&idx.header[0xC0..0xC4], b"TAGX");

        // Entry record: type 1, count 3, then decode entry 0 and check it.
        assert_eq!(u32::from_be_bytes(idx.entries[0x0C..0x10].try_into().unwrap()), 1);
        assert_eq!(u32::from_be_bytes(idx.entries[0x18..0x1C].try_into().unwrap()), 3);
        let e0 = &idx.entries[0xC0..];
        assert_eq!(e0[0], 2); // ident length
        assert_eq!(&e0[1..3], b"00"); // ident
        assert_eq!(e0[3], 0x0F); // control byte
        // offset varint = 3643
        assert_eq!(&e0[4..6], &[0x1c, 0xbb]);

        // CNCX: first label is length-prefixed "Title Page".
        assert_eq!(idx.cncx[0], 0x80 | 10);
        assert_eq!(&idx.cncx[1..11], b"Title Page");
    }
}

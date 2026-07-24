//! The library: a SQLite index plus a managed folder of imported books.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use rusqlite::Connection;

use crate::epub;
use crate::matching;

#[derive(Debug, uniffi::Error)]
pub enum KatalogError {
    Message(String),
}

impl std::fmt::Display for KatalogError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let KatalogError::Message(m) = self;
        write!(f, "{m}")
    }
}
impl std::error::Error for KatalogError {}

impl From<rusqlite::Error> for KatalogError {
    fn from(e: rusqlite::Error) -> Self {
        KatalogError::Message(e.to_string())
    }
}
impl From<std::io::Error> for KatalogError {
    fn from(e: std::io::Error) -> Self {
        KatalogError::Message(e.to_string())
    }
}
impl From<String> for KatalogError {
    fn from(e: String) -> Self {
        KatalogError::Message(e)
    }
}

/// A book as stored in the library.
#[derive(Debug, Clone, uniffi::Record)]
pub struct Book {
    pub id: i64,
    pub title: String,
    pub authors: Vec<String>,
    pub series: Option<String>,
    /// Absolute path to the cached cover image, if any.
    pub cover_path: Option<String>,
    /// Absolute path to the managed epub file.
    pub file_path: String,
    pub format: String,
    pub isbn: Option<String>,
    pub language: Option<String>,
    pub publisher: Option<String>,
    pub description: Option<String>,
    pub added_at: String,
}

/// The editable subset of a book's metadata, applied by [`Library::update`].
/// `cover` carries new image bytes; `None` leaves the current cover untouched.
#[derive(Debug, Clone, uniffi::Record)]
pub struct BookEdit {
    pub title: String,
    pub authors: Vec<String>,
    pub series: Option<String>,
    pub publisher: Option<String>,
    pub isbn: Option<String>,
    pub language: Option<String>,
    pub description: Option<String>,
    /// New cover bytes to set. `None` leaves the cover untouched — unless
    /// `remove_cover` is set, which drops it entirely.
    pub cover: Option<Vec<u8>>,
    pub remove_cover: bool,
}

/// A pending import that matches a book already in the library. Carries the
/// incoming book's preview so the UI can show it next to the existing one.
#[derive(Debug, Clone, uniffi::Record)]
pub struct DuplicateHit {
    pub existing: Book,
    pub incoming_title: String,
    pub incoming_authors: Vec<String>,
    pub incoming_cover: Option<Vec<u8>>,
}

#[derive(uniffi::Object)]
pub struct Library {
    conn: Mutex<Connection>,
    books_dir: PathBuf,
    covers_dir: PathBuf,
}

#[uniffi::export]
impl Library {
    /// Open (creating if needed) a library. `db_path` is the SQLite file,
    /// `books_dir` the managed folder imported epubs are copied into.
    #[uniffi::constructor]
    pub fn open(db_path: String, books_dir: String) -> Result<Arc<Self>, KatalogError> {
        let books_dir = PathBuf::from(books_dir);
        fs::create_dir_all(&books_dir)?;
        // Covers live next to the db, so they survive changing the books folder
        // and work for in-place (non-copied) imports too.
        let covers_dir = Path::new(&db_path)
            .parent()
            .unwrap_or(Path::new("."))
            .join("Covers");
        fs::create_dir_all(&covers_dir)?;
        if let Some(parent) = Path::new(&db_path).parent() {
            fs::create_dir_all(parent)?;
        }
        let conn = Connection::open(&db_path)?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS books (
                id          INTEGER PRIMARY KEY,
                title       TEXT NOT NULL,
                authors     TEXT NOT NULL DEFAULT '',
                series      TEXT,
                cover_path  TEXT,
                file_path   TEXT NOT NULL,
                format      TEXT NOT NULL DEFAULT 'epub',
                isbn        TEXT,
                language    TEXT,
                publisher   TEXT,
                description TEXT,
                added_at    TEXT NOT NULL DEFAULT (datetime('now'))
            );",
        )?;
        Ok(Arc::new(Library {
            conn: Mutex::new(conn),
            books_dir,
            covers_dir,
        }))
    }

    /// Index an epub and cache its cover.
    /// - `copy`: copy the file into the library (Apple Music "copy files").
    ///   When false, the library references the file in place.
    /// - `organize`: when copying, sort into `Author/Title/` folders.
    pub fn import(&self, epub_path: String, copy: bool, organize: bool) -> Result<Book, KatalogError> {
        let src = PathBuf::from(&epub_path);
        let meta = epub::parse(&src)?;
        let author = meta.authors.first().map(String::as_str).unwrap_or("Unknown");

        let file_path = if copy {
            let dest = if organize {
                // "Author/Title - Author.ext" — self-describing, and different
                // formats of one book coexist as same basename + different extension.
                let ext = src.extension().and_then(|e| e.to_str()).unwrap_or("epub");
                self.organized_dest(&meta.title, author, ext)
            } else {
                // ponytail: flat mode keeps the original filename; identical names collide.
                let name = src
                    .file_name()
                    .map(|n| n.to_string_lossy().into_owned())
                    .unwrap_or_else(|| format!("{}.epub", sanitize(&meta.title)));
                self.books_dir.join(name)
            };
            fs::create_dir_all(dest.parent().unwrap_or(&self.books_dir))?;
            fs::copy(&src, &dest)?;
            dest
        } else {
            src.clone()
        };

        // Insert first to get the id, then cache the cover keyed by id.
        let id = {
            let conn = self.lock();
            conn.execute(
                "INSERT INTO books
                    (title, authors, file_path, format, isbn, language, publisher, description)
                 VALUES (?1, ?2, ?3, 'epub', ?4, ?5, ?6, ?7)",
                rusqlite::params![
                    meta.title,
                    meta.authors.join("\n"),
                    file_path.to_string_lossy(),
                    meta.isbn,
                    meta.language,
                    meta.publisher,
                    meta.description,
                ],
            )?;
            conn.last_insert_rowid()
        };

        if let Some(bytes) = &meta.cover {
            // Content-versioned name (see cover_name) — one scheme shared with edits.
            let p = self.covers_dir.join(cover_name(id, bytes));
            fs::write(&p, bytes)?;
            let conn = self.lock();
            conn.execute(
                "UPDATE books SET cover_path = ?1 WHERE id = ?2",
                rusqlite::params![p.to_string_lossy(), id],
            )?;
        }

        self.get(id)?
            .ok_or_else(|| KatalogError::Message("book vanished after insert".into()))
    }

    pub fn list(&self) -> Result<Vec<Book>, KatalogError> {
        let conn = self.lock();
        let mut stmt = conn.prepare(&format!("{SELECT} ORDER BY added_at DESC, id DESC"))?;
        let rows = stmt.query_map([], row_to_book)?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn get(&self, id: i64) -> Result<Option<Book>, KatalogError> {
        let conn = self.lock();
        let mut stmt = conn.prepare(&format!("{SELECT} WHERE id = ?1"))?;
        let mut rows = stmt.query_map([id], row_to_book)?;
        match rows.next() {
            Some(r) => Ok(Some(r?)),
            None => Ok(None),
        }
    }

    /// If an epub matches a book already in the library — same ISBN, or same
    /// title (or a shared ISBN) — return the match plus the incoming book's
    /// preview so the UI can compare them. `None` means no duplicate.
    pub fn find_duplicate(&self, epub_path: String) -> Result<Option<DuplicateHit>, KatalogError> {
        let meta = epub::parse(&PathBuf::from(&epub_path))?;
        let incoming = matching::keys_for(&meta.title, meta.isbn.as_deref());
        // ponytail: linear scan; index a normalized key column if libraries grow huge.
        let existing = self.list()?.into_iter().find(|b| {
            matching::shares_key(&incoming, &matching::keys_for(&b.title, b.isbn.as_deref()))
        });
        match existing {
            Some(existing) => Ok(Some(DuplicateHit {
                existing,
                incoming_title: meta.title,
                incoming_authors: meta.authors,
                incoming_cover: meta.cover,
            })),
            None => Ok(None),
        }
    }

    /// Remove a book from the index. Deletes managed files (the cached cover,
    /// and the epub only if it lives inside the library folder); files
    /// referenced in place are left untouched.
    pub fn remove(&self, id: i64) -> Result<(), KatalogError> {
        let book = self.get(id)?;
        {
            let conn = self.lock();
            conn.execute("DELETE FROM books WHERE id = ?1", [id])?;
        }

        // cover_path is authoritative; the id-named delete is a shim for rows
        // imported before covers were content-versioned.
        if let Some(cp) = book.as_ref().and_then(|b| b.cover_path.as_ref()) {
            let _ = fs::remove_file(cp);
        }
        let _ = fs::remove_file(self.covers_dir.join(id.to_string()));

        if let Some(b) = book {
            let fp = PathBuf::from(&b.file_path);
            // Never delete outside the library (in-place imports live elsewhere).
            if fp.starts_with(&self.books_dir) {
                let _ = fs::remove_file(&fp);
                self.prune_empty_dirs(fp.parent().map(Path::to_path_buf));
            }
        }
        Ok(())
    }

    /// Apply edited metadata: write it back into the epub file, keep the managed
    /// file's Author/Title path in sync (organized libraries only), refresh the
    /// cached cover if a new one was given, and update the index row.
    pub fn update(&self, id: i64, edit: BookEdit) -> Result<Book, KatalogError> {
        let book = self
            .get(id)?
            .ok_or_else(|| KatalogError::Message(format!("no book with id {id}")))?;

        // 1. Write metadata (and any new cover) back into the epub itself.
        let mut file_path = PathBuf::from(&book.file_path);
        if book.format == "epub" && file_path.exists() {
            epub::write_metadata(&file_path, &epub::EpubEdit {
                title: &edit.title,
                authors: &edit.authors,
                publisher: nonempty(&edit.publisher),
                language: nonempty(&edit.language),
                description: nonempty(&edit.description),
                cover: edit.cover.as_deref(),
                remove_cover: edit.remove_cover,
            })?;
        }

        // 2. Reorganize the managed file to match a changed title/author.
        if let Some(new_path) = self.reorganized_path(&file_path, &edit) {
            if new_path != file_path {
                if new_path.exists() {
                    return Err(KatalogError::Message(format!(
                        "a file already exists at {}",
                        new_path.display()
                    )));
                }
                fs::create_dir_all(new_path.parent().unwrap_or(&self.books_dir))?;
                fs::rename(&file_path, &new_path)?;
                self.prune_empty_dirs(file_path.parent().map(Path::to_path_buf));
                file_path = new_path;
            }
        }

        // 3. Refresh the cached cover file the UI reads, and its indexed path.
        // A new cover is written under a content-versioned name so cover_path
        // actually changes — otherwise SwiftUI sees an unchanged path and the
        // grid keeps showing the stale image.
        let cover_path = if edit.remove_cover {
            if let Some(old) = &book.cover_path {
                let _ = fs::remove_file(old);
            }
            None
        } else if let Some(bytes) = &edit.cover {
            let p = self.covers_dir.join(cover_name(id, bytes));
            fs::write(&p, bytes)?;
            if let Some(old) = &book.cover_path {
                if old.as_str() != p.to_string_lossy() {
                    let _ = fs::remove_file(old);
                }
            }
            Some(p.to_string_lossy().into_owned())
        } else {
            book.cover_path.clone()
        };

        // 4. Update the index row.
        {
            let conn = self.lock();
            conn.execute(
                "UPDATE books SET title=?1, authors=?2, series=?3, publisher=?4,
                     isbn=?5, language=?6, description=?7, cover_path=?8, file_path=?9
                 WHERE id=?10",
                rusqlite::params![
                    edit.title,
                    edit.authors.join("\n"),
                    edit.series,
                    edit.publisher,
                    edit.isbn,
                    edit.language,
                    edit.description,
                    cover_path,
                    file_path.to_string_lossy(),
                    id,
                ],
            )?;
        }

        self.get(id)?
            .ok_or_else(|| KatalogError::Message("book vanished after update".into()))
    }

    /// Validate a book is a transferable epub and return its source path.
    /// The platform layer performs the actual copy to the device volume.
    pub fn prepare_transfer(&self, id: i64) -> Result<String, KatalogError> {
        let book = self
            .get(id)?
            .ok_or_else(|| KatalogError::Message(format!("no book with id {id}")))?;
        let path = PathBuf::from(&book.file_path);
        if book.format != "epub" {
            return Err(KatalogError::Message(format!("not an epub: {}", book.format)));
        }
        if !path.exists() {
            return Err(KatalogError::Message(format!("file missing: {}", book.file_path)));
        }
        Ok(book.file_path)
    }
}

/// Match keys for a book's metadata (ISBN + normalized title). Same primitive
/// the device layer uses, so import dedup and "on device" agree.
#[uniffi::export]
pub fn book_keys(title: String, isbn: Option<String>) -> Vec<String> {
    matching::keys_for(&title, isbn.as_deref())
}

/// Convert an epub to a Kindle-native MOBI file at `out_path`.
#[uniffi::export]
pub fn convert_epub_to_mobi(epub_path: String, out_path: String) -> Result<(), KatalogError> {
    crate::mobi::epub_to_mobi(&epub_path, &out_path).map_err(KatalogError::from)
}

/// Match keys for a file on disk. Epub and MOBI/AZW3 are parsed for real
/// metadata; anything else falls back to its filename as the title.
#[uniffi::export]
pub fn file_keys(path: String) -> Result<Vec<String>, KatalogError> {
    let p = PathBuf::from(&path);
    let ext = p
        .extension()
        .and_then(|e| e.to_str())
        .map(str::to_ascii_lowercase)
        .unwrap_or_default();
    match ext.as_str() {
        "epub" => {
            let meta = epub::parse(&p)?;
            Ok(matching::keys_for(&meta.title, meta.isbn.as_deref()))
        }
        // AZW3/KF8 still carry the MOBI EXTH metadata block. Reading files off a
        // device is untrusted, so guard against a parser panic and fall back.
        "mobi" | "azw" | "azw3" | "prc" => {
            let parsed = std::panic::catch_unwind(|| {
                let m = mobi::Mobi::from_path(&p).ok()?;
                Some(matching::keys_for(&m.title(), m.isbn().as_deref()))
            })
            .ok()
            .flatten();
            Ok(parsed.unwrap_or_else(|| matching::keys_for(filestem(&p), None)))
        }
        _ => Ok(matching::keys_for(filestem(&p), None)),
    }
}

fn filestem(p: &Path) -> &str {
    p.file_stem().and_then(|s| s.to_str()).unwrap_or_default()
}

impl Library {

    fn lock(&self) -> std::sync::MutexGuard<'_, Connection> {
        // ponytail: poisoned only if a holder panicked; recover and continue.
        self.conn.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Managed path for the organized layout: `books_dir/Author/Title - Author.ext`.
    fn organized_dest(&self, title: &str, author: &str, ext: &str) -> PathBuf {
        let name = format!("{}.{}", sanitize(&format!("{title} - {author}")), ext);
        self.books_dir.join(sanitize(author)).join(name)
    }

    /// Where an edited book's managed file should live, or `None` if it must not
    /// move: files outside `books_dir` (in-place imports) and flat-layout files
    /// (directly under `books_dir`) keep their path. Organized layout is inferred
    /// from the file already sitting in an `Author/` subfolder.
    fn reorganized_path(&self, current: &Path, edit: &BookEdit) -> Option<PathBuf> {
        if !current.starts_with(&self.books_dir) {
            return None; // in-place import — never move
        }
        if current.parent()? == self.books_dir {
            return None; // flat layout — leave the filename as-is
        }
        let ext = current.extension().and_then(|e| e.to_str()).unwrap_or("epub");
        let author = edit.authors.first().map(String::as_str).unwrap_or("Unknown");
        Some(self.organized_dest(&edit.title, author, ext))
    }

    /// Remove now-empty ancestor folders, walking up from `start` and stopping
    /// at (and never removing) `books_dir`.
    fn prune_empty_dirs(&self, start: Option<PathBuf>) {
        let mut dir = start;
        while let Some(d) = dir {
            if d == self.books_dir || !d.starts_with(&self.books_dir) {
                break;
            }
            if fs::remove_dir(&d).is_err() {
                break; // non-empty or gone — stop
            }
            dir = d.parent().map(Path::to_path_buf);
        }
    }
}

const SELECT: &str = "SELECT id, title, authors, series, cover_path, file_path, \
     format, isbn, language, publisher, description, added_at FROM books";

fn row_to_book(row: &rusqlite::Row) -> rusqlite::Result<Book> {
    let authors: String = row.get(2)?;
    Ok(Book {
        id: row.get(0)?,
        title: row.get(1)?,
        authors: authors.lines().filter(|s| !s.is_empty()).map(str::to_string).collect(),
        series: row.get(3)?,
        cover_path: row.get(4)?,
        file_path: row.get(5)?,
        format: row.get(6)?,
        isbn: row.get(7)?,
        language: row.get(8)?,
        publisher: row.get(9)?,
        description: row.get(10)?,
        added_at: row.get(11)?,
    })
}

/// A trimmed-nonempty view of an optional string, else `None`.
fn nonempty(opt: &Option<String>) -> Option<&str> {
    opt.as_deref().filter(|s| !s.is_empty())
}

/// Cache filename for a cover: `<id>-<content hash>`. The hash makes the path
/// change whenever the image changes, so the UI reloads it (a fixed name would
/// keep the same path and show a stale image).
fn cover_name(id: i64, bytes: &[u8]) -> String {
    use std::hash::{Hash, Hasher};
    let mut h = std::collections::hash_map::DefaultHasher::new();
    bytes.hash(&mut h);
    format!("{id}-{:x}", h.finish())
}

/// Turn a title/author into a safe single path component.
fn sanitize(s: &str) -> String {
    let cleaned: String = s
        .chars()
        .map(|c| if c.is_control() || "/\\:*?\"<>|".contains(c) { '_' } else { c })
        .collect();
    let trimmed = cleaned.trim().trim_matches('.');
    let out: String = trimmed.chars().take(80).collect();
    if out.is_empty() { "_".into() } else { out }
}

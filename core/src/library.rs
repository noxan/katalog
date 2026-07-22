//! The library: a SQLite index plus a managed folder of imported books.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use rusqlite::Connection;

use crate::epub;

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum KatalogError {
    #[error("{0}")]
    Message(String),
}

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

#[derive(uniffi::Object)]
pub struct Library {
    conn: Mutex<Connection>,
    books_dir: PathBuf,
}

#[uniffi::export]
impl Library {
    /// Open (creating if needed) a library. `db_path` is the SQLite file,
    /// `books_dir` the managed folder imported epubs are copied into.
    #[uniffi::constructor]
    pub fn open(db_path: String, books_dir: String) -> Result<Arc<Self>, KatalogError> {
        let books_dir = PathBuf::from(books_dir);
        fs::create_dir_all(&books_dir)?;
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
        }))
    }

    /// Copy an epub into the library, cache its cover, and index it.
    pub fn import(&self, epub_path: String) -> Result<Book, KatalogError> {
        let src = PathBuf::from(&epub_path);
        let meta = epub::parse(&src)?;

        let author = meta.authors.first().map(String::as_str).unwrap_or("Unknown");
        let dest_dir = self
            .books_dir
            .join(sanitize(author))
            .join(sanitize(&meta.title));
        fs::create_dir_all(&dest_dir)?;

        let dest_file = dest_dir.join("book.epub");
        fs::copy(&src, &dest_file)?;

        let cover_path = if let Some(bytes) = &meta.cover {
            // NSImage sniffs content, so the extension is cosmetic.
            let p = dest_dir.join("cover");
            fs::write(&p, bytes)?;
            Some(p.to_string_lossy().into_owned())
        } else {
            None
        };

        let conn = self.lock();
        conn.execute(
            "INSERT INTO books
                (title, authors, cover_path, file_path, format, isbn, language, publisher, description)
             VALUES (?1, ?2, ?3, ?4, 'epub', ?5, ?6, ?7, ?8)",
            rusqlite::params![
                meta.title,
                meta.authors.join("\n"),
                cover_path,
                dest_file.to_string_lossy(),
                meta.isbn,
                meta.language,
                meta.publisher,
                meta.description,
            ],
        )?;
        let id = conn.last_insert_rowid();
        drop(conn);

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

    /// Remove a book from the index and delete its managed folder.
    pub fn remove(&self, id: i64) -> Result<(), KatalogError> {
        let book = self.get(id)?;
        {
            let conn = self.lock();
            conn.execute("DELETE FROM books WHERE id = ?1", [id])?;
        }
        // Best-effort cleanup of the managed folder (parent of book.epub).
        if let Some(dir) = book.and_then(|b| PathBuf::from(b.file_path).parent().map(Path::to_path_buf)) {
            let _ = fs::remove_dir_all(dir);
        }
        Ok(())
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

impl Library {
    fn lock(&self) -> std::sync::MutexGuard<'_, Connection> {
        // ponytail: poisoned only if a holder panicked; recover and continue.
        self.conn.lock().unwrap_or_else(|e| e.into_inner())
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

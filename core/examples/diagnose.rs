//! Diagnose on-device matching: prints the match keys for the library and for
//! a device's documents/ folder, and which books match. Uses the SAME
//! file_keys/book_keys the app uses, so it reflects real behavior.
//!
//! Usage:
//!   cargo run -p katalog-core --example diagnose -- <device_documents_dir> [db_path]
//!
//! Default db_path is the app's: ~/Library/Application Support/Katalog/library.db

use std::collections::HashSet;
use std::path::PathBuf;

use katalog::library::{book_keys, file_keys};
use katalog::Library;

fn main() {
    let mut args = std::env::args().skip(1);
    let docs = args.next().expect("pass the Kindle documents/ path as arg 1");
    let db = args.next().unwrap_or_else(default_db);
    let books_dir = PathBuf::from(&db)
        .parent()
        .unwrap()
        .join("Books")
        .to_string_lossy()
        .into_owned();

    // --- device side ---
    println!("== DEVICE: {docs} ==");
    let mut device_keys: HashSet<String> = HashSet::new();
    let mut files = 0usize;
    for p in walk(PathBuf::from(&docs)) {
        let name = p.file_name().unwrap().to_string_lossy().into_owned();
        files += 1;
        let keys = file_keys(p.to_string_lossy().into_owned()).unwrap_or_default();
        println!("  {name}\n      {keys:?}");
        device_keys.extend(keys);
    }
    println!("  ({files} files, {} device keys)\n", device_keys.len());

    // --- library side ---
    let lib = Library::open(db.clone(), books_dir).expect("open library");
    let library = lib.list().expect("list");
    println!("== LIBRARY: {} books (db {db}) ==", library.len());
    let mut matched = 0;
    for b in &library {
        let keys = book_keys(b.title.clone(), b.isbn.clone());
        let hit = keys.iter().any(|k| device_keys.contains(k));
        if hit {
            matched += 1;
        }
        println!(
            "  [{}] {}\n      {keys:?}",
            if hit { "ON DEVICE" } else { "   --    " },
            b.title
        );
    }
    println!("\n== {matched}/{} matched ==", library.len());
}

const EBOOK_EXTS: &[&str] = &["epub", "mobi", "azw", "azw3", "prc", "kfx"];

/// Recursively collect ebook files, skipping hidden/AppleDouble files and
/// .sdr sidecar folders.
fn walk(root: PathBuf) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let Ok(entries) = std::fs::read_dir(&root) else { return out };
    for entry in entries.flatten() {
        let p = entry.path();
        let name = p.file_name().unwrap_or_default().to_string_lossy();
        if name.starts_with('.') || name.ends_with(".sdr") {
            continue;
        }
        if p.is_dir() {
            out.extend(walk(p));
        } else if p
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| EBOOK_EXTS.contains(&e.to_ascii_lowercase().as_str()))
            .unwrap_or(false)
        {
            out.push(p);
        }
    }
    out
}

fn default_db() -> String {
    let home = std::env::var("HOME").unwrap();
    format!("{home}/Library/Application Support/Katalog/library.db")
}

// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::collections::HashMap;
use std::io::{Read, Seek, Write};

use epub::doc::EpubDoc;
use tauri::api::path::home_dir;

// Learn more about Tauri commands at https://tauri.app/v1/guides/features/command
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct BookEntry {
    name: String,
    path: String,
    metadata: HashMap<String, Vec<String>>,
    cover_image: Option<Vec<u8>>,
    cover_image_file_type: Option<String>,
}

async fn read_book_entry<R: Read + Seek>(
    mut epub: EpubDoc<R>,
) -> (
    HashMap<std::string::String, Vec<std::string::String>>,
    std::option::Option<Vec<u8>>,
    std::option::Option<std::string::String>,
) {
    let cover = epub.get_cover();
    let cover_image = match cover.clone() {
        None => None,
        Some(cover) => Some(cover.0),
    };
    let cover_image_file_type = match cover.clone() {
        None => None,
        Some(cover) => Some(cover.1),
    };

    (epub.metadata, cover_image, cover_image_file_type)
}

#[tauri::command]
async fn read_epub(name: &str, path: &str) -> Result<BookEntry, String> {
    format!("Read file with name {} at path {}.", name, path);

    let epub = match EpubDoc::new(path) {
        Ok(epub) => epub,
        Err(e) => return Err(e.to_string()),
    };

    let (metadata, cover_image, cover_image_file_type) = read_book_entry(epub).await;

    Ok(BookEntry {
        name: String::from(name),
        path: String::from(path),
        metadata: metadata,
        cover_image: cover_image,
        cover_image_file_type: cover_image_file_type,
    })
}

#[tauri::command]
async fn copy_book_to_katalog(name: &str, data: Vec<u8>) -> Result<BookEntry, String> {
    format!("Copy book with name {} to katalog.", name);

    let reader = std::io::Cursor::new(data.clone());

    let epub = match EpubDoc::from_reader(reader) {
        Ok(epub) => epub,
        Err(e) => return Err(e.to_string()),
    };

    let (metadata, cover_image, cover_image_file_type) = read_book_entry(epub).await;

    // write the book file to katalog folder
    let mut path = home_dir().unwrap();
    path.push("Books");
    path.push(name);
    path.set_extension("epub");

    let mut file = match std::fs::File::create(&path) {
        Ok(file) => file,
        Err(e) => return Err(e.to_string()),
    };
    let bytes = &data;
    match file.write_all(&bytes) {
        Ok(_) => (),
        Err(e) => return Err(e.to_string()),
    }

    Ok(BookEntry {
        name: String::from(name),
        path: String::from(name),
        metadata: metadata,
        cover_image: cover_image,
        cover_image_file_type: cover_image_file_type,
    })
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            greet,
            read_epub,
            copy_book_to_katalog
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::collections::HashMap;
use std::fs::File;
use std::io::{self, Read, Seek, Write};

use epub::doc::EpubDoc;
use tauri::api::path::home_dir;
use zip::read::ZipArchive;
use zip::write::FileOptions;
use zip::{CompressionMethod, ZipWriter};

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

async fn edit_epub_interal(path: &str) -> Result<(), io::Error> {
    let mut archive = ZipArchive::new(File::open(path)?)?;
    let mut new_archive = File::create("temp.zip")?;
    let mut zip = ZipWriter::new(&mut new_archive);

    let target_file_name = "test.txt";
    let new_content = "This is the new content for the file";

    let mut file_exists = false;

    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        let options = FileOptions::default()
            .compression_method(CompressionMethod::Stored)
            .unix_permissions(file.unix_mode().unwrap_or(0o755));
        zip.start_file(file.name().to_string(), options)?;

        if file.name() == target_file_name {
            zip.write_all(new_content.as_bytes())?;
            file_exists = true;
        } else {
            std::io::copy(&mut file, &mut zip)?;
        }
    }

    if !file_exists {
        zip.start_file(target_file_name, FileOptions::default())?;
        zip.write_all(new_content.as_bytes())?;
    }

    zip.finish()?;

    std::fs::rename("temp.zip", path)?;

    Ok(())
}

#[tauri::command]
async fn edit_epub(path: &str) -> Result<(), String> {
    format!("Edit epub.");

    match edit_epub_interal(path).await {
        Err(e) => return Err(e.to_string()),
        Ok(_) => (),
    }

    Ok(())
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            greet,
            read_epub,
            edit_epub,
            copy_book_to_katalog
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::collections::HashMap;
use std::fs::File;
use std::io::{self, Read, Seek, Write};
use std::path::PathBuf;

use epub::doc::EpubDoc;
use tauri::path::BaseDirectory;
use tauri::{AppHandle, Manager, Runtime};
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
    cover_image_path: Option<PathBuf>,
    cover_image: Option<Vec<u8>>,
    cover_image_file_type: Option<String>,
}

async fn read_book_entry<R: Read + Seek>(
    mut epub: EpubDoc<R>,
) -> (
    HashMap<std::string::String, Vec<std::string::String>>,
    std::option::Option<PathBuf>,
    std::option::Option<Vec<u8>>,
    std::option::Option<std::string::String>,
) {
    let cover_image_path;
    {
        let cover_resource = match epub.get_cover_id() {
            None => None,
            Some(cover_resource) => epub.resources.get(&cover_resource).cloned(),
        };
        cover_image_path = match cover_resource {
            None => None,
            Some(cover_resource) => Some(cover_resource.0),
        };
    }
    let cover = epub.get_cover();
    let cover_image = match cover.clone() {
        None => None,
        Some(cover) => Some(cover.0),
    };
    let cover_image_file_type = match cover.clone() {
        None => None,
        Some(cover) => Some(cover.1),
    };

    (
        epub.metadata,
        cover_image_path,
        cover_image,
        cover_image_file_type,
    )
}

#[tauri::command]
async fn read_epub(name: &str, path: &str) -> Result<BookEntry, String> {
    format!("Read file with name {} at path {}.", name, path);

    let epub = match EpubDoc::new(path) {
        Ok(epub) => epub,
        Err(e) => return Err(e.to_string()),
    };

    let (metadata, cover_image_path, cover_image, cover_image_file_type) =
        read_book_entry(epub).await;

    Ok(BookEntry {
        name: String::from(name),
        path: String::from(path),
        metadata: metadata,
        cover_image_path: cover_image_path,
        cover_image: cover_image,
        cover_image_file_type: cover_image_file_type,
    })
}

#[tauri::command]
async fn copy_book_to_katalog<R: Runtime>(app: AppHandle<R>, name: &str, data: Vec<u8>) -> Result<BookEntry, String> {
    format!("Copy book with name {} to katalog.", name);

    let reader = std::io::Cursor::new(data.clone());

    let epub = match EpubDoc::from_reader(reader) {
        Ok(epub) => epub,
        Err(e) => return Err(e.to_string()),
    };

    let (metadata, cover_image_path, cover_image, cover_image_file_type) =
        read_book_entry(epub).await;

    // write the book file to katalog folder
    let mut path = app.path().resolve("Books", BaseDirectory::Home).unwrap();
    // path.push("Books");
    path.push(name);
    path.set_extension("epub");
    println!("Path: {:?}", path);

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
        cover_image_path: cover_image_path,
        cover_image: cover_image,
        cover_image_file_type: cover_image_file_type,
    })
}

fn add_or_replace_file_in_epub(
    zip_path: &str,
    target_file_name: &str,
    target_file_content: Vec<u8>,
) -> Result<(), io::Error> {
    let mut archive = ZipArchive::new(File::open(zip_path)?)?;
    let mut new_archive = File::create("temp.zip")?;
    let mut zip = ZipWriter::new(&mut new_archive);

    let mut file_exists = false;

    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        let options = FileOptions::default()
            .compression_method(CompressionMethod::Stored)
            .unix_permissions(file.unix_mode().unwrap_or(0o755));
        zip.start_file(file.name().to_string(), options)?;

        if file.name() == target_file_name {
            zip.write_all(&target_file_content)?;
            file_exists = true;
        } else {
            std::io::copy(&mut file, &mut zip)?;
        }
    }

    if !file_exists {
        zip.start_file(target_file_name, FileOptions::default())?;
        zip.write_all(&target_file_content)?;
    }

    zip.finish()?;

    std::fs::rename("temp.zip", zip_path)?;

    Ok(())
}

#[tauri::command]
async fn edit_epub_cover(
    path: &str,
    target_file_name: &str,
    cover_image: Vec<u8>,
) -> Result<(), String> {
    match add_or_replace_file_in_epub(path, target_file_name, cover_image) {
        Err(e) => return Err(e.to_string()),
        Ok(_) => (),
    }
    Ok(())
}

fn edit_epub_metadata_internal(
    zip_path: &str,
    values: HashMap<&str, &str>,
) -> Result<(), io::Error> {
    let mut archive = ZipArchive::new(File::open(zip_path)?)?;
    let mut new_archive = File::create("temp.zip")?;
    let mut zip = ZipWriter::new(&mut new_archive);

    // Assume we have a valid container file in the epub
    let target_file_name = "META-INF/container.xml";

    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        let options = FileOptions::default()
            .compression_method(CompressionMethod::Stored)
            .unix_permissions(file.unix_mode().unwrap_or(0o755));
        zip.start_file(file.name().to_string(), options)?;

        if file.name() == target_file_name {
            let mut buffer = Vec::new();
            file.read_to_end(&mut buffer)?;

            let content = String::from_utf8(buffer.clone()).unwrap();
            println!("Content: {}", content);

            zip.write_all(&buffer)?;
        } else {
            std::io::copy(&mut file, &mut zip)?;
        }
    }

    zip.finish()?;

    std::fs::rename("temp.zip", zip_path)?;

    Ok(())
}

#[tauri::command]
async fn edit_epub_metadata(path: &str, values: HashMap<&str, &str>) -> Result<(), String> {
    println!("Edit file at path {} with {:?}.", path, values.keys());

    match edit_epub_metadata_internal(path, values) {
        Err(e) => return Err(e.to_string()),
        Ok(_) => (),
    }

    Ok(())
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![
            greet,
            read_epub,
            edit_epub_metadata,
            edit_epub_cover,
            copy_book_to_katalog
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::collections::HashMap;

use epub::doc::EpubDoc;

// Learn more about Tauri commands at https://tauri.app/v1/guides/features/command
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

#[derive(serde::Serialize)]
struct BookEntry {
    name: String,
    path: String,
    metadata: HashMap<String, Vec<String>>,
}

#[tauri::command]
fn read_epub(name: &str, path: &str) -> BookEntry {
    format!("Read file with name {} at path {}.", name, path);
    let epub = EpubDoc::new(path).unwrap();

    return BookEntry {
        name: String::from(name),
        path: String::from(path),
        metadata: epub.metadata,
    };
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![greet])
        .invoke_handler(tauri::generate_handler![read_epub])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

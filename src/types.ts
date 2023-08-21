import { FileEntry } from "@tauri-apps/api/fs";

export type BookEntry = FileEntry & { metadata?: any; coverImage?: string };

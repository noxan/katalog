import { FileEntry } from "@tauri-apps/api/fs";

export type BookEntry = FileEntry & { metadata?: any; coverImage?: string };

export type KatalogStatus =
  | "initialize"
  | "loading:entries"
  | "loading:details"
  | "ready";

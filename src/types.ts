import { FileEntry } from "@tauri-apps/api/fs";

export type BookEntry = FileEntry & { metadata?: any; coverImage?: string };

export enum KatalogStatus {
  INITIALIZE = "initialize",
  LOADING_ENTRIES = "loading:entries",
  LOADING_DETAILS = "loading:details",
  READY = "ready",
}

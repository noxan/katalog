import { invoke } from "@tauri-apps/api/core";
import { mkdir, exists, readDir, BaseDirectory } from "@tauri-apps/plugin-fs";
import { bytesToBase64 } from "byte-base64";
import type { BookEntry, FileEntry } from "../types";

export const BASE_DIRECTORY = BaseDirectory.Home;
export const KATALOG_PATH = "Books";

export const ensureKatalogDirectory = async () => {
  if (!(await exists(KATALOG_PATH, { baseDir: BASE_DIRECTORY }))) {
    await mkdir(KATALOG_PATH, { baseDir: BASE_DIRECTORY });
  }
};

export const initializeEntries = async (): Promise<BookEntry[]> => {
  await ensureKatalogDirectory();

  // TODO: recursive loading of files
  const entries = await readDir(KATALOG_PATH, { baseDir: BASE_DIRECTORY });

  return entries
    .filter((entry) => entry.isFile)
    .filter((entry) => entry.name.endsWith(".epub"))
    .map((entry) => ({
      name: entry.name,
      path: entry.name,
    })) as FileEntry[];
};

const encodeCoverImage = async (bytes: Uint8Array) => {
  const coverImageBase64: string = await bytesToBase64(bytes);
  return `data:image/jpg;charset=utf-8;base64,${coverImageBase64}`;
};

export const readEpub = async (entry: FileEntry): Promise<BookEntry> => {
  const epub = await invoke<BookEntry>("read_epub", { ...entry });
  if (epub.coverImage) {
    epub.coverImage = await encodeCoverImage(
      epub.coverImage as unknown as Uint8Array,
    );
  }
  return epub;
};

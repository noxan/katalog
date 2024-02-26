import { invoke } from "@tauri-apps/api/core";
import {
  mkdir,
  exists,
  readDir,
  BaseDirectory,
  DirEntry as FileEntry,
} from "@tauri-apps/plugin-fs";
import { bytesToBase64 } from "byte-base64";
import { BookEntry } from "../types";

export const BASE_DIRECTORY = BaseDirectory.Home;
export const KATALOG_PATH = "Books";

export const ensureKatalogDirectory = async () => {
  if (!(await exists(KATALOG_PATH, { baseDir: BASE_DIRECTORY }))) {
    await mkdir(KATALOG_PATH, { baseDir: BASE_DIRECTORY });
  }
};

const flattenFileEntries = (array: FileEntry[]): FileEntry[] =>
  array.reduce<FileEntry[]>((acc, item) => {
    if (item.children) {
      return [...acc, ...flattenFileEntries(item.children)];
    }
    return [...acc, item];
  }, []);

const filterFileEntries = (entries: FileEntry[]) =>
  entries.filter((entry) => entry.name?.endsWith(".epub"));

export const initializeEntries = async (): Promise<BookEntry[]> => {
  await ensureKatalogDirectory();

  const nestedEntries = await readDir(KATALOG_PATH, {
    baseDir: BASE_DIRECTORY,
  });
  const entries = flattenFileEntries(nestedEntries);

  return filterFileEntries(entries);
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

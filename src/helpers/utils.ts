import {
  createDir,
  exists,
  readDir,
  BaseDirectory,
  FileEntry,
} from "@tauri-apps/api/fs";
import { encodeCoverImage } from "./epub";
import { BookEntry } from "../types";
import { invoke } from "@tauri-apps/api";

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
  const dir = BaseDirectory.Home;
  const path = "Books";

  if (!(await exists(path, { dir }))) {
    await createDir(path, { dir });
  }

  const nestedEntries = await readDir(path, { dir, recursive: true });
  const entries = flattenFileEntries(nestedEntries);

  return filterFileEntries(entries);
};

export const readEpub = async (entry: FileEntry): Promise<BookEntry> => {
  const epub = await invoke<BookEntry>("read_epub", { ...entry });
  if (epub.coverImage) {
    epub.coverImage = await encodeCoverImage(
      epub.coverImage as unknown as Uint8Array
    );
  }
  return epub;
};

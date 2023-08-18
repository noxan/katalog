import {
  createDir,
  exists,
  readDir,
  BaseDirectory,
  FileEntry,
} from "@tauri-apps/api/fs";
import { readEpub } from "./Epub";

export type BookEntry = FileEntry & { metadata?: any; coverImage?: string };

const flattenFileEntries = (array: FileEntry[]): FileEntry[] =>
  array.reduce<FileEntry[]>((acc, item) => {
    if (item.children) {
      return [...acc, ...flattenFileEntries(item.children)];
    }
    return [...acc, item];
  }, []);

const filterFileEntries = (entries: FileEntry[]) =>
  entries.filter((entry) => entry.name?.endsWith(".epub"));

export const initialize = async (): Promise<BookEntry[]> => {
  const dir = BaseDirectory.Home;
  const path = "Books";

  if (!(await exists(path, { dir }))) {
    await createDir(path, { dir });
  }

  const nestedEntries = await readDir(path, { dir, recursive: true });
  const entries = flattenFileEntries(nestedEntries);

  return filterFileEntries(entries);
};

export const initializeBook = async (entry: FileEntry): Promise<BookEntry> => {
  const epub = await readEpub(entry);
  return { ...epub, ...entry } as BookEntry;
};

export const initializeBooks = async (
  entries: FileEntry[]
): Promise<BookEntry[]> =>
  Promise.all(entries.map(async (entry) => await initializeBook(entry)));

export async function bufferToBase64(buffer: Uint8Array) {
  // use a FileReader to generate a base64 data URI:
  const base64url: any = await new Promise((r) => {
    const reader = new FileReader();
    reader.onload = () => r(reader.result);
    reader.readAsDataURL(new Blob([buffer]));
  });
  // remove the `data:...;base64,` part from the start
  return base64url.slice(base64url.indexOf(",") + 1);
}

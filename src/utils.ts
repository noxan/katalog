import {
  createDir,
  exists,
  readDir,
  BaseDirectory,
  FileEntry,
} from "@tauri-apps/api/fs";

export type BookEntry = FileEntry & { metadata: object };

const flattenFileEntries = (array: FileEntry[]): FileEntry[] =>
  array.reduce<FileEntry[]>((acc, item) => {
    if (item.children) {
      return [...acc, ...flattenFileEntries(item.children)];
    }
    return [...acc, item];
  }, []);

const filterFileEntries = (entries: FileEntry[]) =>
  entries.filter((entry) => entry.name?.endsWith(".epub"));

export const initialize = async () => {
  const dir = BaseDirectory.Home;
  const path = "Books";

  if (!(await exists(path, { dir }))) {
    await createDir(path, { dir });
  }

  const nestedEntries = await readDir(path, { dir, recursive: true });
  const entries = flattenFileEntries(nestedEntries);

  return filterFileEntries(entries);
};

const initializeBook = async (entry: FileEntry): Promise<BookEntry> => {
  return { ...entry, metadata: {} } as BookEntry;
};

export const initializeBooks = async (
  entries: FileEntry[]
): Promise<BookEntry[]> =>
  Promise.all(entries.map(async (entry) => initializeBook(entry)));

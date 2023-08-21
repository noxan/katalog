import { create } from "zustand";
import { ACCEPTED_MIME_TYPES, BookEntry, KatalogStatus } from "../types";
import { initializeEntries, readEpub } from "../helpers/utils";
import { invoke } from "@tauri-apps/api";

interface KatalogStore {
  status: KatalogStatus;
  entries: BookEntry[];
  initializeKatalog: () => void;
  copyBooksToKatalog: (files: File[]) => void;
  importBook: () => void;
}

const replaceEntryByPath = (entries: BookEntry[], newEntry: BookEntry) =>
  entries.map((entry) => (entry.path === newEntry.path ? newEntry : entry));

export const useKatalogStore = create<KatalogStore>((set) => ({
  status: KatalogStatus.INITIALIZE,
  entries: [],
  importBook: () =>
    set((state) => ({
      entries: [...state.entries, { name: "test-name", path: "test-path" }],
    })),
  copyBooksToKatalog: async (files: File[]) => {
    const epubFiles = files.filter((file) =>
      ACCEPTED_MIME_TYPES.includes(file.type)
    );
    epubFiles.map(async (file) => {
      const arrayBuffer = await file.arrayBuffer();
      const bytes = new Uint8Array(arrayBuffer);
      const data = Array.from(bytes);
      const payload = { name, data };
      const book = await invoke<BookEntry>("copy_book_to_katalog", payload);
      set((state) => ({ entries: [...state.entries, book] }));
    });
  },
  initializeKatalog: async () => {
    set({ status: KatalogStatus.LOADING_ENTRIES });
    const entries = await initializeEntries();
    set({ status: KatalogStatus.LOADING_DETAILS, entries });
    await Promise.all(
      entries.map(async (entry) => {
        const epub = await readEpub(entry);
        set((state) => ({ entries: replaceEntryByPath(state.entries, epub) }));
      })
    );
    set({ status: KatalogStatus.READY });
  },
}));

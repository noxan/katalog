import { create } from "zustand";
import { BookEntry, KatalogStatus } from "../types";
import { initializeEntries, readEpub } from "../helpers/utils";

interface KatalogStore {
  status: KatalogStatus;
  entries: BookEntry[];
  initializeKatalog: () => void;
  copyBookToKatalog: (name: string, bytes: Uint8Array) => void;
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
  copyBookToKatalog: (name, bytes) => {
    console.log("copyBookToKatalog", name, bytes.length);
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

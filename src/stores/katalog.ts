import { create } from "zustand";
import { BookEntry, KatalogStatus } from "../types";
import { initialize, readEpub } from "../helpers/utils";

interface KatalogStore {
  status: KatalogStatus;
  entries: BookEntry[];
  initializeKatalog: () => void;
  importBook: () => void;
}

export const useKatalogStore = create<KatalogStore>((set) => ({
  status: KatalogStatus.INITIALIZE,
  entries: [],
  importBook: () =>
    set((state) => ({
      entries: [...state.entries, { name: "test-name", path: "test-path" }],
    })),
  initializeKatalog: async () => {
    set({ status: KatalogStatus.LOADING_ENTRIES });
    const entries = await initialize();
    set({ status: KatalogStatus.LOADING_DETAILS, entries });
    await Promise.all(
      entries.map(async (entry) => {
        const epub = await readEpub(entry);
        set((state) => ({
          entries: state.entries.map((entry) =>
            entry.path === epub.path ? epub : entry
          ),
        }));
      })
    );
    set({ status: KatalogStatus.READY });
  },
}));

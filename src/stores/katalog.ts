import { create } from "zustand";
import { BookEntry, KatalogStatus } from "../types";

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
    await new Promise((resolve) => setTimeout(resolve, 1000));
    set({ status: KatalogStatus.READY });
  },
}));

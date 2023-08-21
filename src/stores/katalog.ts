import { create } from "zustand";
import { BookEntry } from "../types";

interface KatalogStore {
  status: "initialize" | "loading" | "ready";
  entries: BookEntry[];
  initializeKatalog: () => void;
  importBook: () => void;
}

export const useKatalogStore = create<KatalogStore>((set) => ({
  status: "initialize",
  entries: [],
  importBook: () =>
    set((state) => ({
      entries: [...state.entries, { name: "test-name", path: "test-path" }],
    })),
  initializeKatalog: async () => {
    set({ status: "loading" });
    await new Promise((resolve) => setTimeout(resolve, 1000));
    set({ status: "ready" });
  },
}));

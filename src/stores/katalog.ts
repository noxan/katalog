import { create } from "zustand";
import { BookEntry } from "../helpers/utils";

interface KatalogStore {
  status: "initialize" | "loading" | "ready";
  entries: BookEntry[];
  importBook: () => void;
}

export const useKatalogStore = create<KatalogStore>((set) => ({
  status: "initialize",
  entries: [],
  importBook: () =>
    set((state) => ({
      entries: [...state.entries, { name: "test-name", path: "test-path" }],
    })),
}));

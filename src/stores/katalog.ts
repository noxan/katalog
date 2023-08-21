import { create } from "zustand";
import { BookEntry, KatalogStatus } from "../types";
import { initialize } from "../helpers/utils";
import { encodeCoverImage } from "../helpers/epub";
import { invoke } from "@tauri-apps/api";

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
        const epub = (await invoke("read_epub", {
          name: entry.name,
          path: entry.path,
        })) as BookEntry;
        if (epub.coverImage) {
          epub.coverImage = await encodeCoverImage(
            epub.coverImage as unknown as Uint8Array
          );
        }
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

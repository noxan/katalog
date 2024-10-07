export type FileEntry = {
  name: string;
  path: string;
};

export type BookEntry = FileEntry & {
  metadata?: Record<string, string | undefined>;
  coverImagePath?: string;
  coverImage?: string;
};

export enum KatalogStatus {
  INITIALIZE = "initialize",
  LOADING_ENTRIES = "loading:entries",
  LOADING_DETAILS = "loading:details",
  LOADING_IMPORT = "loading:import",
  READY = "ready",
}

export const ACCEPTED_MIME_TYPES = ["application/epub+zip"];

import { Dispatch, createContext, useEffect, useReducer } from "react";
import { BookEntry, initialize } from "./utils";
import { invoke } from "@tauri-apps/api/tauri";
import { encodeCoverImage } from "./epub";

type Status = "initialize" | "loading:entries" | "loading:details" | "ready";
type KatalogContextType = {
  status: Status;
  entries: BookEntry[];
};

let firstRun = true;

const defaultValue = {
  status: "initialize" as Status,
  entries: [] as BookEntry[],
};

export const KatalogContext = createContext<KatalogContextType>(defaultValue);

const initializeKatalog = async (dispatch: Dispatch<any>) => {
  dispatch({
    type: "initialize",
    payload: { status: "loading:entries" },
  });
  const entries = await initialize();
  dispatch({
    type: "initialize",
    payload: { status: "loading:entries", entries },
  });
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
      dispatch({
        type: "initialize",
        payload: {
          status: "loading:entries",
          entries: entries.map((e) => (e.path === entry.path ? epub : e)),
        },
      });
    })
  );
  dispatch({
    type: "initialize",
    payload: { status: "ready" },
  });
};

export function KatalogProvider({ children }: { children: React.ReactNode }) {
  const [entries, dispatch] = useReducer(katalogReducer, defaultValue);

  useEffect(() => {
    if (firstRun) {
      firstRun = false;
      initializeKatalog(dispatch);
    }
  }, []);

  return (
    <KatalogContext.Provider value={entries}>
      {children}
    </KatalogContext.Provider>
  );
}

function katalogReducer(previous: KatalogContextType, action: any) {
  switch (action.type) {
    case "initialize":
      return { ...previous, ...action.payload };
    default: {
      throw Error("Unknown action: " + action.type);
    }
  }
}

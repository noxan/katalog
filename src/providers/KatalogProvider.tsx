import { Dispatch, createContext, useEffect, useReducer } from "react";
import { initialize } from "../helpers/utils";
import { invoke } from "@tauri-apps/api/tauri";
import { encodeCoverImage } from "../helpers/epub";
import { BookEntry, KatalogStatus } from "../types";

type KatalogContextType = {
  status: KatalogStatus;
  entries: BookEntry[];
};

const defaultValue = {
  status: "initialize" as KatalogStatus,
  entries: [] as BookEntry[],
};

export const KatalogContext = createContext<KatalogContextType>(defaultValue);
export const KatalogDispatchContext = createContext<Dispatch<any> | null>(null);

export const initializeKatalog = async (dispatch: Dispatch<any>) => {};

export function KatalogProvider({ children }: { children: React.ReactNode }) {
  const [entries, dispatch] = useReducer(katalogReducer, defaultValue);

  return (
    <KatalogContext.Provider value={entries}>
      <KatalogDispatchContext.Provider value={dispatch}>
        {children}
      </KatalogDispatchContext.Provider>
    </KatalogContext.Provider>
  );
}

function katalogReducer(previous: KatalogContextType, action: any) {
  switch (action.type) {
    case "initialize":
      return { ...previous, ...action.payload };
    case "initialize:epub":
      return {
        ...previous,
        entries: previous.entries.map((entry) =>
          entry.path === action.payload.path ? action.payload : entry
        ),
      };
    default: {
      throw Error("Unknown action: " + action.type);
    }
  }
}

import { createContext, useReducer } from "react";
import { BookEntry } from "./utils";

export const KatalogContext = createContext<BookEntry[]>([]);

export function KatalogProvider({ children }: { children: React.ReactNode }) {
  const [tasks, _dispatch] = useReducer(katalogReducer, []);

  return (
    <KatalogContext.Provider value={tasks}>{children}</KatalogContext.Provider>
  );
}

function katalogReducer(entries: BookEntry[], action: { type: string }) {
  switch (action.type) {
    case "added": {
      return [...entries];
    }
    default: {
      throw Error("Unknown action: " + action.type);
    }
  }
}

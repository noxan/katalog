import { createContext, useEffect, useReducer } from "react";
import { BookEntry } from "./utils";

let firstRun = true;

export const KatalogContext = createContext<BookEntry[]>([]);

export function KatalogProvider({ children }: { children: React.ReactNode }) {
  const [tasks, _dispatch] = useReducer(katalogReducer, []);

  useEffect(() => {
    const setup = async () => {
      if (firstRun) {
        firstRun = false;
        console.log("initialize");
      }
    };
    setup();
  }, []);

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

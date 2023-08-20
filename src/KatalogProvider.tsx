import { createContext, useEffect, useReducer } from "react";
import { BookEntry, initialize } from "./utils";

let firstRun = true;

export const KatalogContext = createContext<BookEntry[]>([]);

export function KatalogProvider({ children }: { children: React.ReactNode }) {
  const [tasks, dispatch] = useReducer(katalogReducer, []);

  useEffect(() => {
    const setup = async () => {
      if (firstRun) {
        firstRun = false;
        const entries = await initialize();
        dispatch({ type: "initialize", entries });
      }
    };
    setup();
  }, []);

  return (
    <KatalogContext.Provider value={tasks}>{children}</KatalogContext.Provider>
  );
}

function katalogReducer(entries: BookEntry[], action: any) {
  switch (action.type) {
    case "initialize":
      return action.entries;
    case "added": {
      return [...entries];
    }
    default: {
      throw Error("Unknown action: " + action.type);
    }
  }
}

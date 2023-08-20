import { createContext, useEffect, useReducer } from "react";
import { BookEntry, initialize } from "./utils";

type Status = "initialize" | "loading:entries" | "loading:details" | "ready";
type KatalogContext = {
  status: Status;
  entries: BookEntry[];
};

let firstRun = true;

export const KatalogContext = createContext<KatalogContext>({
  status: "initialize",
  entries: [],
});

export function KatalogProvider({ children }: { children: React.ReactNode }) {
  const [entries, dispatch] = useReducer(katalogReducer, []);

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
    <KatalogContext.Provider value={entries}>
      {children}
    </KatalogContext.Provider>
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

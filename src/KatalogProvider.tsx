import { createContext, useEffect, useReducer } from "react";
import { BookEntry, initialize } from "./utils";

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


export function KatalogProvider({ children }: { children: React.ReactNode }) {
  const [entries, dispatch] = useReducer(katalogReducer, defaultValue);

  useEffect(() => {
    const setup = async () => {
      if (firstRun) {
        firstRun = false;
        const entries = await initialize();
        dispatch({
          type: "initialize",
          payload: { status: "loading:entries", entries },
        });
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
      return action.payload;
    case "added": {
      return [...entries];
    }
    default: {
      throw Error("Unknown action: " + action.type);
    }
  }
}

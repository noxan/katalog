import { useEffect, useState } from "react";
import { Center, Container, Button } from "@mantine/core";
import { FileEntry } from "@tauri-apps/api/fs";
import { initialize } from "./utils";

type Status = "initialize" | "loading" | "ready";

function App() {
  const [status, setStatus] = useState<Status>("initialize");
  const [entries, setEntries] = useState<FileEntry[]>([]);

  useEffect(() => {
    if (status === "initialize") {
      initialize().then((entries) => {
        setEntries(entries);
        setStatus("ready");
      });
    }
  }, [status]);

  return (
    <Center>
      <Container>
        <h1>Welcome to Tauri!</h1>

        <p>{status}</p>
        <Button
          disabled={status === "loading"}
          onClick={async () => setEntries(await initialize())}
        >
          Initalize
        </Button>

        <ul>
          {entries.map((entry) => (
            <li key={entry.name}>{entry.name}</li>
          ))}
        </ul>
      </Container>
    </Center>
  );
}

export default App;

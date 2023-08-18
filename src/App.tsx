import { useState } from "react";
import { Center, Container, Button } from "@mantine/core";
import { FileEntry } from "@tauri-apps/api/fs";
import { initialize } from "./utils";

function App() {
  const [entries, setEntries] = useState<FileEntry[]>([]);

  return (
    <Center>
      <Container>
        <h1>Welcome to Tauri!</h1>

        <Button onClick={async () => setEntries(await initialize())}>
          Initalize
        </Button>

        <ul>
          {entries.map((entry) => (
            <li key={entry.name}>{JSON.stringify(entry)}</li>
          ))}
        </ul>
      </Container>
    </Center>
  );
}

export default App;

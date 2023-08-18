import { useState } from "react";
import { Center, Container, Button } from "@mantine/core";
import {
  createDir,
  exists,
  readDir,
  BaseDirectory,
  FileEntry,
} from "@tauri-apps/api/fs";

const flattenFileEntries = (array: FileEntry[]): FileEntry[] =>
  array.reduce<FileEntry[]>((acc, item) => {
    if (item.children) {
      return [...acc, ...flattenFileEntries(item.children)];
    }
    return [...acc, item];
  }, []);

const initialize = async () => {
  const dir = BaseDirectory.Home;
  const path = "Books";

  if (!(await exists(path, { dir }))) {
    await createDir(path, { dir });
  }

  const nestedEntries = await readDir(path, { dir, recursive: true });
  const entries = flattenFileEntries(nestedEntries);

  console.log(entries);
  return entries;
};

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

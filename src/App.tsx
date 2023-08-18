import { useState } from "react";
import { Center, Container, Button, Group, Input } from "@mantine/core";
import { invoke } from "@tauri-apps/api/tauri";
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
  const [greetMsg, setGreetMsg] = useState("");
  const [name, setName] = useState("");
  const [entries, setEntries] = useState<FileEntry[]>([]);

  async function greet() {
    // Learn more about Tauri commands at https://tauri.app/v1/guides/features/command
    setGreetMsg(await invoke("greet", { name }));
  }

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

        <form
          className="row"
          onSubmit={(e) => {
            e.preventDefault();
            greet();
          }}
        >
          <Group>
            <Input
              id="greet-input"
              onChange={(e) => setName(e.currentTarget.value)}
              placeholder="Enter a name..."
            />

            <Button type="submit">Greet</Button>
          </Group>
        </form>

        <p>{greetMsg}</p>
      </Container>
    </Center>
  );
}

export default App;

import { useState } from "react";
import { Center, Container, Button, Group, Input } from "@mantine/core";
import { invoke } from "@tauri-apps/api/tauri";

function App() {
  const [greetMsg, setGreetMsg] = useState("");
  const [name, setName] = useState("");

  async function greet() {
    // Learn more about Tauri commands at https://tauri.app/v1/guides/features/command
    setGreetMsg(await invoke("greet", { name }));
  }

  return (
    <Container>
      <h1>Welcome to Tauri!</h1>

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

      <Center>
        <p>{greetMsg}</p>
      </Center>
    </Container>
  );
}

export default App;

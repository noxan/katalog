import { useEffect, useState } from "react";
import {
  Center,
  Container,
  Button,
  Grid,
  Card,
  Text,
  Image,
  Group,
} from "@mantine/core";
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

        <Grid gutter="lg">
          {entries.map((entry) => (
            <Grid.Col key={entry.name} span={3}>
              <Card shadow="sm" padding="lg" radius="md" withBorder>
                <Card.Section>
                  <Image
                    height={120}
                    src={null}
                    alt="Book cover image"
                    withPlaceholder
                    placeholder={<Text align="center">Book cover</Text>}
                  />
                </Card.Section>
                <Group position="apart" mt="md">
                  <Text
                    weight={500}
                    style={{
                      overflow: "hidden",
                      whiteSpace: "nowrap",
                      textOverflow: "ellipsis",
                    }}
                  >
                    {entry.name?.trim()}
                  </Text>
                </Group>
              </Card>
            </Grid.Col>
          ))}
        </Grid>
      </Container>
    </Center>
  );
}

export default App;

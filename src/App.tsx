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
import { BookEntry, initialize, initializeBooks } from "./utils";

type Status = "initialize" | "loading:entries" | "loading:details" | "ready";

function App() {
  const [status, setStatus] = useState<Status>("initialize");
  const [entries, setEntries] = useState<BookEntry[]>([]);

  const initializeKatalog = async () => {
    setStatus("loading:entries");
    const entries = await initialize();
    setEntries(entries);
    setStatus("loading:details");
    setEntries(await initializeBooks(entries));
    setStatus("ready");
  };

  useEffect(() => {
    if (status === "initialize") {
      initializeKatalog();
    }
  }, [status]);

  return (
    <Center>
      <Container>
        <h1>Welcome to Tauri!</h1>

        <Group mb="md">
          <Button
            disabled={status.startsWith("loading")}
            onClick={initializeKatalog}
          >
            Reload
          </Button>
          <Text>{status}</Text>
        </Group>

        <Grid gutter="lg">
          {entries.map((entry) => (
            <Grid.Col key={entry.name} span={3}>
              <Card shadow="sm" padding="lg" radius="md" withBorder>
                <Card.Section>
                  <Image
                    height={200}
                    src={status === "ready" ? entry?.metadata?.cover : null}
                    alt="Book cover image"
                    withPlaceholder
                    placeholder={
                      <Text align="center" m="xs">
                        {entry.name}
                      </Text>
                    }
                  />
                </Card.Section>
                <Group position="apart" mt="md">
                  <Text
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

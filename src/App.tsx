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
import { BookEntry, initialize, initializeBook } from "./utils";

type Status = "initialize" | "loading:entries" | "loading:details" | "ready";

function App() {
  const [status, setStatus] = useState<Status>("initialize");
  const [entries, setEntries] = useState<BookEntry[]>([]);

  const initializeKatalog = async () => {
    setStatus("loading:entries");
    const entries = await initialize();
    setEntries(entries);
    setStatus("loading:details");
    await Promise.all(
      entries.map(async (entry) => {
        const book = await initializeBook(entry);
        setEntries((entries) =>
          entries.map((e) => (e.path === entry.path ? book : e))
        );
        return book;
      })
    );
    setStatus("ready");
  };

  useEffect(() => {
    if (status === "initialize") {
      initializeKatalog();
    }
  }, [status]);

  const displayTitle = (entry: BookEntry) => {
    const title = entry?.metadata?.["dc:title"] ?? entry.name;
    return typeof title === "object" ? title["#text"] : title;
  };

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
                    {displayTitle(entry)}
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

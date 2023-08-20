import { Dispatch, useContext } from "react";
import {
  Center,
  Container,
  Button,
  Card,
  Text,
  Image,
  Group,
  SimpleGrid,
  Title,
} from "@mantine/core";
import { BookEntry } from "./utils";
import {
  KatalogContext,
  KatalogDispatchContext,
  initializeKatalog as initializeKatalogAction,
} from "./KatalogProvider";

function Katalog() {
  const { status, entries } = useContext(KatalogContext);
  const dispatch = useContext(KatalogDispatchContext);

  const initializeKatalog = () =>
    initializeKatalogAction(dispatch as Dispatch<any>);

  const displayTitle = (entry: BookEntry) => {
    const title = entry?.metadata?.["dc:title"] ?? entry.name;
    return typeof title === "object" ? title["#text"] : title;
  };

  return (
    <Container fluid>
      <Center>
        <Container>
          <Title my="md">Welcome to Katalog!</Title>

          <Group mb="md">
            <Button
              disabled={status.startsWith("loading")}
              onClick={initializeKatalog}
            >
              Reload
            </Button>
            <Text>{status}</Text>
          </Group>
        </Container>
      </Center>

      {/* <Container>
        <Text>{JSON.stringify(entries[0])}</Text>
      </Container> */}

      <SimpleGrid
        cols={5}
        breakpoints={[
          { maxWidth: "96rem", cols: 4, spacing: "md" },
          { maxWidth: "64rem", cols: 3, spacing: "md" },
          { maxWidth: "48rem", cols: 2, spacing: "sm" },
          { maxWidth: "36rem", cols: 1, spacing: "sm" },
        ]}
      >
        {entries.map((entry) => (
          <Card
            key={entry.name}
            shadow="sm"
            padding="lg"
            radius="md"
            withBorder
          >
            <Card.Section>
              <Image
                height={200}
                src={entry?.coverImage}
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
        ))}
      </SimpleGrid>
    </Container>
  );
}

export default Katalog;

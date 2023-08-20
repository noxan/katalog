import { useContext } from "react";
import { Container, Card, Text, Image, Group, SimpleGrid } from "@mantine/core";
import { BookEntry } from "../utils";
import { KatalogContext } from "../providers/KatalogProvider";

export default function KatalogRoute() {
  const { entries } = useContext(KatalogContext);

  const displayTitle = (entry: BookEntry) => {
    const title = entry?.metadata?.["dc:title"] ?? entry.name;
    return typeof title === "object" ? title["#text"] : title;
  };

  return (
    <Container fluid>
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

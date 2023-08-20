import { useContext } from "react";
import { Container, SimpleGrid } from "@mantine/core";
import { KatalogContext } from "../providers/KatalogProvider";
import { BookCard } from "../components/BookCard";

export default function KatalogRoute() {
  const { entries } = useContext(KatalogContext);

  return (
    <Container fluid mb="md">
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
          <BookCard entry={entry} />
        ))}
      </SimpleGrid>
    </Container>
  );
}

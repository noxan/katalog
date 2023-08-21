import { Container, SimpleGrid } from "@mantine/core";
import { BookCard } from "../components/BookCard";
import { EmptyLibrary } from "../components/EmptyLibrary";
import { useKatalogStore } from "../stores/katalog";

export default function KatalogRoute() {
  const entries = useKatalogStore((state) => state.entries);

  if (entries.length <= 0) {
    return <EmptyLibrary />;
  }

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
          <BookCard key={entry.name} entry={entry} />
        ))}
      </SimpleGrid>
    </Container>
  );
}

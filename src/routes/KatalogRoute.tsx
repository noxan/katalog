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
        cols={{ base: 1, xs: 2, sm: 3, md: 3, lg: 4, xl: 5 }}
        spacing={{ base: "sm", md: "md" }}
      >
        {entries.map((entry) => (
          <BookCard key={entry.name} entry={entry} />
        ))}
      </SimpleGrid>
    </Container>
  );
}

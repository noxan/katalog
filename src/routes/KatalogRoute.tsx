import { Container, SimpleGrid } from "@mantine/core";
import { Dropzone } from "@mantine/dropzone";
import { BookCard } from "../components/BookCard";
import DropzoneContent from "../components/DropzoneContent";
import { EmptyLibrary } from "../components/EmptyLibrary";
import { useKatalogStore } from "../stores/katalog";
import { ACCEPTED_MIME_TYPES } from "../types";

export default function KatalogRoute() {
  const entries = useKatalogStore((state) => state.entries);
  const copyBooksToKatalog = useKatalogStore(
    (state) => state.copyBooksToKatalog,
  );

  if (entries.length <= 0) {
    return <EmptyLibrary />;
  }

  return (
    <Container fluid mb="md">
      <Dropzone.FullScreen
        onDrop={copyBooksToKatalog}
        accept={ACCEPTED_MIME_TYPES}
      >
        <DropzoneContent />
      </Dropzone.FullScreen>
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

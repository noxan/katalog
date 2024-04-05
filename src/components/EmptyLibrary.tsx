import { Container } from "@mantine/core";
import { Dropzone } from "@mantine/dropzone";
import { useKatalogStore } from "../stores/katalog";
import { ACCEPTED_MIME_TYPES } from "../types";
import DropzoneContent from "./DropzoneContent";

export function EmptyLibrary() {
  const copyBooksToKatalog = useKatalogStore(
    (state) => state.copyBooksToKatalog,
  );

  return (
    <Container fluid mb="md">
      <Dropzone onDrop={copyBooksToKatalog} accept={ACCEPTED_MIME_TYPES}>
        <DropzoneContent />
      </Dropzone>
    </Container>
  );
}

import { Container, Group, Text, rem } from "@mantine/core";
import { Dropzone } from "@mantine/dropzone";
import { IconBooks, IconUpload, IconX } from "@tabler/icons-react";
import { useKatalogStore } from "../stores/katalog";
import { ACCEPTED_MIME_TYPES } from "../types";

export function EmptyLibrary() {
  const copyBooksToKatalog = useKatalogStore(
    (state) => state.copyBooksToKatalog,
  );

  return (
    <Container fluid mb="md">
      <Dropzone onDrop={copyBooksToKatalog} accept={ACCEPTED_MIME_TYPES}>
        <Group
          justify="center"
          gap="xl"
          style={{ minHeight: rem(220), pointerEvents: "none" }}
        >
          <Dropzone.Accept>
            <IconUpload size="3.2rem" stroke={1.5} />
          </Dropzone.Accept>
          <Dropzone.Reject>
            <IconX size="3.2rem" stroke={1.5} />
          </Dropzone.Reject>
          <Dropzone.Idle>
            <IconBooks size="3.2rem" stroke={1.5} />
          </Dropzone.Idle>

          <div>
            <Text size="xl" inline>
              Drag ebooks here or click to select files
            </Text>
            <Text size="sm" color="dimmed" inline mt={7}>
              Attach as many files as you like, each file should not exceed 5mb
            </Text>
          </div>
        </Group>
      </Dropzone>
    </Container>
  );
}

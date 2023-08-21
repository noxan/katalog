import { Container, Group, Text, rem, useMantineTheme } from "@mantine/core";
import { Dropzone } from "@mantine/dropzone";
import { IconBooks, IconUpload, IconX } from "@tabler/icons-react";
import { useKatalogStore } from "../stores/katalog";

const EPUB_MIME_TYPE = ["application/epub+zip"];

export function EmptyLibrary() {
  const theme = useMantineTheme();
  const copyBookToKatalog = useKatalogStore((state) => state.copyBookToKatalog);

  const handleDrop = (files: File[]) => {
    const epubFiles = files.filter((file) =>
      EPUB_MIME_TYPE.includes(file.type)
    );
    epubFiles.map(async (file) => {
      const arrayBuffer = await file.arrayBuffer();
      const bytes = new Uint8Array(arrayBuffer);
      await copyBookToKatalog(file.name, bytes);
    });
  };

  return (
    <Container fluid mb="md">
      <Dropzone onDrop={handleDrop} accept={EPUB_MIME_TYPE}>
        <Group
          position="center"
          spacing="xl"
          style={{ minHeight: rem(220), pointerEvents: "none" }}
        >
          <Dropzone.Accept>
            <IconUpload
              size="3.2rem"
              stroke={1.5}
              color={
                theme.colors[theme.primaryColor][
                  theme.colorScheme === "dark" ? 4 : 6
                ]
              }
            />
          </Dropzone.Accept>
          <Dropzone.Reject>
            <IconX
              size="3.2rem"
              stroke={1.5}
              color={theme.colors.red[theme.colorScheme === "dark" ? 4 : 6]}
            />
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

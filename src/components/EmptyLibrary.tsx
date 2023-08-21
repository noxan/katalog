import { Button, Container, Text } from "@mantine/core";
import { IconBooks } from "@tabler/icons-react";

export function EmptyLibrary() {
  return (
    <Container fluid mb="md">
      <IconBooks strokeWidth={1} size={128} />

      <Text>There are no books in the katalog.</Text>
      <Button mt="md">Import book</Button>
    </Container>
  );
}

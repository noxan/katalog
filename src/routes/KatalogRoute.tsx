import { Container, Text } from "@mantine/core";
import { useContext } from "react";
import { KatalogContext } from "../KatalogProvider";

export default function KatalogRoute() {
  const entries = useContext(KatalogContext);

  return (
    <Container>
      <Text>KatalogRoute</Text>
      <ul>
        {entries.map((entry) => (
          <li key={entry.name}>{JSON.stringify(entry)}</li>
        ))}
      </ul>
    </Container>
  );
}

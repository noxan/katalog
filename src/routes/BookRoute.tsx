import { Container, Text } from "@mantine/core";
import { useContext } from "react";
import { useParams } from "react-router";
import { KatalogContext } from "../providers/KatalogProvider";

export default function BookRoute() {
  const { name } = useParams();
  const { entries } = useContext(KatalogContext);
  const entry = entries.filter((value) => value.name === name);

  return (
    <Container>
      <Text>BookRoute</Text>
      <Text>{JSON.stringify(entry)}</Text>
    </Container>
  );
}

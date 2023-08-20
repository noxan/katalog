import { Container, Image, Text } from "@mantine/core";
import { useContext } from "react";
import { useParams } from "react-router";
import { KatalogContext } from "../providers/KatalogProvider";

export default function BookRoute() {
  const { name } = useParams();
  const { entries } = useContext(KatalogContext);
  const entry = entries.filter((value) => value.name === name)[0];

  return (
    <Container>
      <Text>BookRoute</Text>
      <Image src={entry.coverImage} height={300} width={200} />
      <Text>{JSON.stringify(entry)}</Text>
    </Container>
  );
}

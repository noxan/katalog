import { Container, Image, Text, Title } from "@mantine/core";
import { useContext } from "react";
import { useParams } from "react-router";
import { KatalogContext } from "../providers/KatalogProvider";

export default function BookRoute() {
  const { name } = useParams();
  const { entries } = useContext(KatalogContext);
  const entry = entries.filter((value) => value.name === name)[0];

  return (
    <Container>
      <Image src={entry.coverImage} height={300} width={200} />
      <Title>{entry.metadata.title}</Title>
      <Text>{JSON.stringify(entry.metadata)}</Text>
    </Container>
  );
}

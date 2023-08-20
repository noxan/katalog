import { Button, Container, Group, Image, Text, Title } from "@mantine/core";
import { useContext } from "react";
import { useParams, Link } from "react-router-dom";
import { KatalogContext } from "../providers/KatalogProvider";

export default function BookRoute() {
  const { name } = useParams();
  const { entries } = useContext(KatalogContext);
  const entry = entries.filter((value) => value.name === name)[0];

  return (
    <Container mb="md">
      <Group>
        <Link to="/">
          <Button variant="light">Back</Button>
        </Link>
        <Link to="./edit">
          <Button variant="light">Edit</Button>
        </Link>
      </Group>
      <Image src={entry.coverImage} height={300} width={200} />
      <Title>{entry.metadata.title}</Title>
      {Object.keys(entry.metadata).map((key) => (
        <Text key={key}>
          <b>{key}</b>: {entry.metadata[key]}
        </Text>
      ))}
    </Container>
  );
}

import { Button, Container, Group, Image, Text, Title } from "@mantine/core";
import { useParams, Link } from "react-router-dom";
import { useKatalogStore } from "../stores/katalog";

export default function BookRoute() {
  const { name } = useParams();
  const entries = useKatalogStore((store) => store.entries);
  const status = useKatalogStore((store) => store.status);
  const entry = entries.filter((value) => value.name === name)[0];

  if (status !== "ready") {
    return <Container>Loading...</Container>;
  }

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

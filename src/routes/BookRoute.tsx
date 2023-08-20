import { Container, Image, Text, Title } from "@mantine/core";
import { useContext } from "react";
import { useParams } from "react-router";
import { Link } from "react-router-dom";
import { KatalogContext } from "../providers/KatalogProvider";

export default function BookRoute() {
  const { name } = useParams();
  const { entries } = useContext(KatalogContext);
  const entry = entries.filter((value) => value.name === name)[0];

  return (
    <Container>
      <Link to="/">Back</Link>
      <Image src={entry.coverImage} height={300} width={200} />
      <Title>{entry.metadata.title}</Title>
      {Object.keys(entry.metadata).map((key) => (
        <Text key={key}>
          {key}: {entry.metadata[key]}
        </Text>
      ))}
    </Container>
  );
}

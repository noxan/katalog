import {
  Button,
  Container,
  Flex,
  Group,
  Image,
  Text,
  Title,
} from "@mantine/core";
import { Link, useParams } from "react-router-dom";
import { useKatalogStore } from "../stores/katalog";

export default function BookRoute() {
  const { name } = useParams();
  const entries = useKatalogStore((store) => store.entries);
  const status = useKatalogStore((store) => store.status);
  const entry = entries.filter((value) => value.name === name)[0];

  if (status !== "ready") {
    return <Container>Loading...</Container>;
  }

  const imageLongEdge = 500;
  const imageRatio = 2 / 3;
  const imageShortEdge = imageLongEdge * imageRatio;

  return (
    <Container mb="md">
      <Flex gap="md" direction={{ base: "column", sm: "row" }}>
        <div>
          <Image
            src={entry.coverImage}
            height={imageLongEdge}
            width={imageShortEdge}
          />
          <Group>
            <Link to="/">
              <Button variant="light">Back</Button>
            </Link>
            <Link to="./edit">
              <Button variant="light">Edit</Button>
            </Link>
          </Group>
        </div>
        <div>
          <Title>{entry.metadata.title}</Title>
          {Object.keys(entry.metadata).map((key) => (
            <Text key={key}>
              <b>{key}</b>: {entry.metadata[key]}
            </Text>
          ))}
        </div>
      </Flex>
    </Container>
  );
}

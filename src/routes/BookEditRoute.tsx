import {
  Button,
  Container,
  Group,
  Image,
  NumberInput,
  TextInput,
  Textarea,
} from "@mantine/core";
import { useContext } from "react";
import { useParams, Link } from "react-router-dom";
import { KatalogContext } from "../providers/KatalogProvider";

export default function BookEditRoute() {
  const { name } = useParams();
  const { entries } = useContext(KatalogContext);
  const entry = entries.filter((value) => value.name === name)[0];

  return (
    <Container mb="md">
      <Link to={`/books/${name}`}>
        <Button variant="light">Back</Button>
      </Link>
      <TextInput label="Title" />
      <TextInput label="Author" />
      <Group grow>
        <TextInput label="Series" />
        <NumberInput label="Position" />
      </Group>
      <TextInput label="Rating" />
      <TextInput label="Tags" />
      <TextInput label="Ids" />
      <TextInput label="Date modified" />
      <TextInput label="Published" />
      <TextInput label="Publisher" />
      <TextInput label="Languages" />
      <Textarea label="Comments" />

      <Image src={entry.coverImage} height={300} width={200} />
    </Container>
  );
}

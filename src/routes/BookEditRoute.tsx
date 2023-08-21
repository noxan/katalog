import {
  Button,
  Container,
  Group,
  Image,
  NumberInput,
  TextInput,
  Textarea,
} from "@mantine/core";
import { useParams, Link } from "react-router-dom";
import { useKatalogStore } from "../stores/katalog";

export default function BookEditRoute() {
  const { name } = useParams();
  const entries = useKatalogStore((store) => store.entries);
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

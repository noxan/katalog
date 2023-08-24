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
import { invoke } from "@tauri-apps/api/tauri";
import { Dropzone, FileWithPath, IMAGE_MIME_TYPE } from "@mantine/dropzone";
import { BookEntry } from "../types";

export default function BookEditRoute() {
  const { name } = useParams();
  const entries = useKatalogStore((store) => store.entries);
  const entry = entries.filter((value) => value.name === name)[0];

  const replaceCoverImage = async (entry: BookEntry, files: FileWithPath[]) => {
    const file = files[0];
    const arrayBuffer = await file.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);
    const data = Array.from(bytes);
    console.log(entry.path, entry.coverImagePath);
    invoke("edit_epub", {
      path: entry.path,
      targetFileName: entry.coverImagePath,
      coverImage: data,
    });
  };

  return (
    <Container mb="md">
      <Link to={`/books/${name}`}>
        <Button variant="light">Back</Button>
      </Link>

      <Dropzone
        multiple={false}
        accept={IMAGE_MIME_TYPE}
        onDrop={(files) => replaceCoverImage(entry, files)}
      >
        Drop files here
      </Dropzone>

      {/* <Button onClick={() => editEpub()}>Edit</Button> */}

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

import {
  Button,
  Container,
  Group,
  Image,
  Input,
  NumberInput,
  TextInput,
  Textarea,
} from "@mantine/core";
import { useForm } from "@mantine/form";
import { useParams, Link } from "react-router-dom";
import { useKatalogStore } from "../stores/katalog";
import { invoke } from "@tauri-apps/api/tauri";
import { Dropzone, FileWithPath, IMAGE_MIME_TYPE } from "@mantine/dropzone";
import { BookEntry } from "../types";
import { useId } from "@mantine/hooks";

export default function BookEditRoute() {
  const { name } = useParams();
  const id = useId();
  const status = useKatalogStore((store) => store.status);
  const entries = useKatalogStore((store) => store.entries);
  const entry = entries.filter((value) => value.name === name)[0];
  const form = useForm({
    initialValues: {
      title: entry?.metadata?.title ?? "",
      date: entry?.metadata?.date ?? "",
    },
  });

  if (status !== "ready") {
    return <Container>Loading...</Container>;
  }

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
      <Input.Wrapper id={id} label="Cover image">
        <Dropzone
          id={id}
          multiple={false}
          accept={IMAGE_MIME_TYPE}
          onDrop={(files) => replaceCoverImage(entry, files)}
        >
          <Image src={entry.coverImage} height={150} width={100} />
          Drop new cover image here to replace the previous one.
        </Dropzone>
      </Input.Wrapper>

      <form onSubmit={form.onSubmit((values) => console.log(values))}>
        <TextInput label="Title" {...form.getInputProps("title")} />
        {/* <TextInput label="Author" />
      <Group grow>
        <TextInput label="Series" />
        <NumberInput label="Position" />
      </Group>
      <TextInput label="Rating" />
      <TextInput label="Tags" />
      <TextInput label="Ids" />
      <TextInput label="Date modified" /> */}
        <TextInput label="Published" {...form.getInputProps("date")} />
        {/* <TextInput label="Publisher" />
      <TextInput label="Languages" />
      <Textarea label="Comments" /> */}

        <Group mt="md">
          <Link to={`/books/${name}`}>
            <Button variant="light">Back</Button>
          </Link>
          <Button type="submit">Save</Button>
        </Group>
      </form>
    </Container>
  );
}

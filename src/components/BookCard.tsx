import { AspectRatio, Card, Group, Image, Text } from "@mantine/core";
import { Link } from "react-router-dom";
import { BookEntry } from "../helpers/utils";

const displayTitle = (entry: BookEntry) => {
  const title = entry?.metadata?.["dc:title"] ?? entry.name;
  return typeof title === "object" ? title["#text"] : title;
};

export const BookCard = ({ entry }: { entry: BookEntry }) => (
  <Card
    key={entry.name}
    shadow="sm"
    padding="lg"
    radius="md"
    withBorder
    component={Link}
    to={`/books/${entry.name}`}
  >
    <Card.Section>
      <AspectRatio ratio={0.75}>
        <Image
          src={entry?.coverImage}
          alt="Book cover image"
          withPlaceholder
          placeholder={
            <Text align="center" m="xs">
              {entry.name}
            </Text>
          }
        />
      </AspectRatio>
    </Card.Section>
    <Group position="apart" mt="md">
      <Text
        style={{
          overflow: "hidden",
          whiteSpace: "nowrap",
          textOverflow: "ellipsis",
        }}
      >
        {displayTitle(entry)}
      </Text>
    </Group>
  </Card>
);

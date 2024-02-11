import { AspectRatio, Card, Image } from "@mantine/core";
import { Link } from "react-router-dom";
import { BookEntry } from "../types";
import classes from "./BookCard.module.css";

const displayTitle = (entry: BookEntry) => {
  return entry?.metadata?.title ?? entry.name;
};

export const BookCard = ({ entry }: { entry: BookEntry }) => {
  return (
    <Card
      key={entry.name}
      shadow="sm"
      padding="lg"
      radius="md"
      withBorder
      component={Link}
      to={`/books/${entry.name}`}
      className={classes.card}
    >
      <Card.Section>
        <AspectRatio ratio={2 / 3}>
          <Image src={entry?.coverImage} alt={displayTitle(entry)} />
        </AspectRatio>
      </Card.Section>
    </Card>
  );
};

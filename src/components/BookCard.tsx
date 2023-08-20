import { AspectRatio, Card, Image, Text, createStyles } from "@mantine/core";
import { Link } from "react-router-dom";
import { BookEntry } from "../helpers/utils";

const displayTitle = (entry: BookEntry) => {
  return entry?.metadata?.title ?? entry.name;
};

const animationStyle = "150ms cubic-bezier(0.4,0,0.2,1)";

const useStyles = createStyles((theme) => ({
  card: {
    position: "relative",
    transition: `transform ${animationStyle}`,
    "&:hover": {
      boxShadow: theme.shadows.md,
      transform: "scale(1.02)",
    },
  },
}));

export const BookCard = ({ entry }: { entry: BookEntry }) => {
  const { classes } = useStyles();

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
        <AspectRatio ratio={0.75}>
          <Image
            src={entry?.coverImage}
            alt="Book cover image"
            withPlaceholder
            placeholder={
              <Text align="center" m="xs">
                {displayTitle(entry)}
              </Text>
            }
          />
        </AspectRatio>
      </Card.Section>
    </Card>
  );
};

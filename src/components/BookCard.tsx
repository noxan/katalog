import {
  AspectRatio,
  Card,
  Group,
  Image,
  Text,
  createStyles,
} from "@mantine/core";
import { useHover } from "@mantine/hooks";
import { Link } from "react-router-dom";
import { BookEntry } from "../helpers/utils";

const displayTitle = (entry: BookEntry) => {
  const title = entry?.metadata?.["dc:title"] ?? entry.name;
  return typeof title === "object" ? title["#text"] : title;
};

const useStyles = createStyles((theme) => ({
  card: {
    position: "relative",
    transition: "transform 100ms ease-in",
    "&:hover": {
      boxShadow: theme.shadows.md,
      transform: "scale(1.02)",
    },
  },
  title: {
    transition: "opacity 100ms ease-in",
    position: "absolute",
    bottom: 0,
    background: "rgba(0,0,0,0.5)",
    paddingLeft: theme.spacing.md,
    paddingRight: theme.spacing.md,
    paddingTop: theme.spacing.sm,
    paddingBottom: theme.spacing.sm,
  },
}));

export const BookCard = ({ entry }: { entry: BookEntry }) => {
  const { hovered, ref } = useHover();
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
      <Card.Section ref={ref}>
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
        <div className={classes.title} style={{ opacity: hovered ? 1 : 0 }}>
          <Text
            style={{
              overflow: "hidden",
              whiteSpace: "nowrap",
              textOverflow: "ellipsis",
            }}
          >
            {displayTitle(entry)}
          </Text>
        </div>
      </Card.Section>
    </Card>
  );
};

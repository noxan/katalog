import {
  Button,
  FileButton,
  Group,
  Header,
  Text,
  createStyles,
  rem,
} from "@mantine/core";
import { useKatalogStore } from "../stores/katalog";
import { ACCEPTED_MIME_TYPES } from "../types";

const useStyles = createStyles((theme) => ({
  header: {
    paddingLeft: theme.spacing.md,
    paddingRight: theme.spacing.md,
  },
  inner: {
    height: rem(56),
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
  },
}));

export function KatalogHeader() {
  const copyBooksToKatalog = useKatalogStore(
    (state) => state.copyBooksToKatalog
  );
  const initializeKatalog = useKatalogStore((state) => state.initializeKatalog);
  const status = useKatalogStore((state) => state.status);
  const { classes } = useStyles();

  return (
    <Header height={56} className={classes.header} mb="md">
      <div className={classes.inner}>
        <Group>
          <Text my="md">Welcome to Katalog!</Text>
        </Group>

        <Group>
          <Text>{status}</Text>
          <Button
            disabled={status.startsWith("loading")}
            onClick={initializeKatalog}
          >
            Reload
          </Button>
          <FileButton
            accept={ACCEPTED_MIME_TYPES.join(",")}
            disabled={status.startsWith("loading")}
            onChange={(file: File) => copyBooksToKatalog([file])}
          >
            {(props) => <Button {...props}>Import</Button>}
          </FileButton>
        </Group>
      </div>
    </Header>
  );
}

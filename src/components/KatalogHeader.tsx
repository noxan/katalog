import { Dispatch, useContext } from "react";
import { Button, Group, Header, Text, createStyles, rem } from "@mantine/core";
import {
  KatalogContext,
  KatalogDispatchContext,
  initializeKatalog as initializeKatalogAction,
} from "../providers/KatalogProvider";
import { useKatalogStore } from "../stores/katalog";

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
  const importBook = useKatalogStore((state) => state.importBook);
  const { status } = useContext(KatalogContext);
  const dispatch = useContext(KatalogDispatchContext);
  const { classes } = useStyles();

  const initializeKatalog = () =>
    initializeKatalogAction(dispatch as Dispatch<any>);

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
          <Button disabled={status.startsWith("loading")} onClick={importBook}>
            Import
          </Button>
        </Group>
      </div>
    </Header>
  );
}

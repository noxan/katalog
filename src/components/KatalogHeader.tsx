import { AppShell, Button, FileButton, Group, Text } from "@mantine/core";
import { useKatalogStore } from "../stores/katalog";
import { ACCEPTED_MIME_TYPES } from "../types";

import classes from "./KatalogHeader.module.css";

export function KatalogHeader() {
  const copyBooksToKatalog = useKatalogStore(
    (state) => state.copyBooksToKatalog
  );
  const initializeKatalog = useKatalogStore((state) => state.initializeKatalog);
  const status = useKatalogStore((state) => state.status);

  return (
    <AppShell.Header className={classes.header} mb="md">
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
            onChange={(file: File | null) => {
              if (file) {
                copyBooksToKatalog([file]);
              }
            }}
          >
            {(props) => (
              <Button disabled={status.startsWith("loading")} {...props}>
                Import
              </Button>
            )}
          </FileButton>
        </Group>
      </div>
    </AppShell.Header>
  );
}

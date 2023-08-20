import { Dispatch, useContext } from "react";
import { Button, Center, Container, Group, Text, Title } from "@mantine/core";
import {
  KatalogContext,
  KatalogDispatchContext,
  initializeKatalog as initializeKatalogAction,
} from "../KatalogProvider";

export function KatalogHeader() {
  const { status } = useContext(KatalogContext);
  const dispatch = useContext(KatalogDispatchContext);

  const initializeKatalog = () =>
    initializeKatalogAction(dispatch as Dispatch<any>);

  return (
    <Center>
      <Container m="md">
        <Title my="md">Welcome to Katalog!</Title>

        <Group mb="md">
          <Button
            disabled={status.startsWith("loading")}
            onClick={initializeKatalog}
          >
            Reload
          </Button>
          <Text>{status}</Text>
        </Group>
      </Container>
    </Center>
  );
}

import { AppShell } from "@mantine/core";
import { Outlet } from "react-router-dom";
import { KatalogHeader } from "../components/KatalogHeader";

export default function RootRoute() {
  return (
    <AppShell padding="md" header={{ height: 56 }}>
      <KatalogHeader />
      <AppShell.Main>
        <Outlet />
      </AppShell.Main>
    </AppShell>
  );
}

import { MantineProvider } from "@mantine/core";

export default function ThemeProvider({ children }: any) {
  return (
    <MantineProvider defaultColorScheme="auto">{children}</MantineProvider>
  );
}

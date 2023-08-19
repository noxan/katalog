import { useEffect, useState } from "react";
import {
  ColorScheme,
  ColorSchemeProvider,
  MantineProvider,
} from "@mantine/core";
import { useColorScheme, useMediaQuery } from "@mantine/hooks";
import Katalog from "./Katalog";

function App() {
  const isMediaDarkMode = useMediaQuery("(prefers-color-scheme: dark)");
  const preferredColorScheme = useColorScheme();
  const [colorScheme, setColorScheme] =
    useState<ColorScheme>(preferredColorScheme);
  const toggleColorScheme = (value?: ColorScheme) =>
    setColorScheme(value || (colorScheme === "dark" ? "light" : "dark"));

  useEffect(() => {
    if (isMediaDarkMode) {
      setColorScheme("dark");
    } else {
      setColorScheme("light");
    }
  }, [preferredColorScheme]);

  return (
    <ColorSchemeProvider
      colorScheme={colorScheme}
      toggleColorScheme={toggleColorScheme}
    >
      <MantineProvider
        theme={{ colorScheme }}
        withGlobalStyles
        withNormalizeCSS
      >
        <Katalog />
      </MantineProvider>
    </ColorSchemeProvider>
  );
}

export default App;

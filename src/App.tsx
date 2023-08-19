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
  console.log(isMediaDarkMode);
  const preferredColorScheme = useColorScheme();
  console.log(preferredColorScheme);
  const [colorScheme, setColorScheme] =
    useState<ColorScheme>(preferredColorScheme);
  const toggleColorScheme = (value?: ColorScheme) =>
    setColorScheme(value || (colorScheme === "dark" ? "light" : "dark"));

  console.log("colorScheme", colorScheme);
  useEffect(() => {
    console.log("useEffect", isMediaDarkMode);
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

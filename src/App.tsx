import { MantineProvider } from "@mantine/core";
import Katalog from "./Katalog";

function App() {
  return (
    <MantineProvider
      theme={{ colorScheme: "dark" }}
      withGlobalStyles
      withNormalizeCSS
    >
      <Katalog />
    </MantineProvider>
  );
}

export default App;

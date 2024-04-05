import { useEffect } from "react";
import { RouterProvider, createBrowserRouter } from "react-router-dom";
import BookEditRoute from "../routes/BookEditRoute";
import BookRoute from "../routes/BookRoute";
import KatalogRoute from "../routes/KatalogRoute";
import RootRoute from "../routes/RootRoute";
import { useKatalogStore } from "../stores/katalog";

import { MantineProvider } from "@mantine/core";
import "@mantine/core/styles.css";
import "@mantine/dropzone/styles.css";

const router = createBrowserRouter([
  {
    path: "/",
    element: <RootRoute />,
    children: [
      {
        index: true,
        element: <KatalogRoute />,
      },
      {
        path: "/books/:name",
        element: <BookRoute />,
      },
      {
        path: "/books/:name/edit",
        element: <BookEditRoute />,
      },
    ],
  },
]);

let firstRun = true;

function App() {
  const initializeKatalog = useKatalogStore((state) => state.initializeKatalog);
  useEffect(() => {
    if (firstRun) {
      firstRun = false;
      initializeKatalog();
    }
  }, [initializeKatalog]);
  return (
    <MantineProvider defaultColorScheme="auto">
      <RouterProvider router={router} />
    </MantineProvider>
  );
}

export default App;

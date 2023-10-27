import { createBrowserRouter, RouterProvider } from "react-router-dom";
import ThemeProvider from "../providers/ThemeProvider";
import RootRoute from "../routes/RootRoute";
import KatalogRoute from "../routes/KatalogRoute";
import BookRoute from "../routes/BookRoute";
import BookEditRoute from "../routes/BookEditRoute";
import { useEffect } from "react";
import { useKatalogStore } from "../stores/katalog";

import "@mantine/core/styles.css";

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
  }, []);
  return (
    <ThemeProvider>
      <RouterProvider router={router} />
    </ThemeProvider>
  );
}

export default App;

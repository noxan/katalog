import { createBrowserRouter, RouterProvider } from "react-router-dom";
import ThemeProvider from "../providers/ThemeProvider";
import KatalogRoute from "../routes/KatalogRoute";
import BookRoute from "../routes/BookRoute";
import { KatalogProvider } from "../providers/KatalogProvider";
import { KatalogHeader } from "./KatalogHeader";

const router = createBrowserRouter([
  {
    path: "/",
    element: <KatalogRoute />,
  },
  {
    path: "/books/:name",
    element: <BookRoute />,
  },
]);

function App() {
  return (
    <ThemeProvider>
      <KatalogProvider>
        <KatalogHeader />
        <RouterProvider router={router} />
      </KatalogProvider>
    </ThemeProvider>
  );
}

export default App;

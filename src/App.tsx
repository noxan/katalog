import { createBrowserRouter, RouterProvider } from "react-router-dom";
import ThemeProvider from "./ThemeProvider";
import Katalog from "./Katalog";
import KatalogRoute from "./routes/KatalogRoute";
import BookRoute from "./routes/BookRoute";
import { KatalogProvider } from "./KatalogProvider";

const router = createBrowserRouter([
  {
    path: "/",
    element: <KatalogRoute />,
  },
  {
    path: "/book",
    element: <BookRoute />,
  },
]);

function App() {
  return (
    <ThemeProvider>
      <KatalogProvider>
        <RouterProvider router={router} />
      </KatalogProvider>
    </ThemeProvider>
  );
}

export default App;

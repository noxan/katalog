import { createBrowserRouter, RouterProvider } from "react-router-dom";
import ThemeProvider from "./ThemeProvider";
import KatalogRoute from "./routes/KatalogRoute";
import BookRoute from "./routes/BookRoute";
import { KatalogProvider } from "./KatalogProvider";
import { KatalogHeader } from "./components/KatalogHeader";

const router = createBrowserRouter([
  {
    path: "/",
    element: <KatalogRoute />,
  },
  {
    path: "/book/:id",
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

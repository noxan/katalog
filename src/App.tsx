import { createBrowserRouter, RouterProvider } from "react-router-dom";
import ThemeProvider from "./ThemeProvider";
import Katalog from "./Katalog";
import KatalogRoute from "./routes/KatalogRoute";
import BookRoute from "./routes/BookRoute";

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
      <Katalog>
        <RouterProvider router={router} />
      </Katalog>
    </ThemeProvider>
  );
}

export default App;

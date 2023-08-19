import { createBrowserRouter, RouterProvider } from "react-router-dom";
import ThemeProvider from "./ThemeProvider";
import Katalog from "./Katalog";

const router = createBrowserRouter([
  {
    path: "/",
    element: <Katalog />,
  },
]);

function App() {
  return (
    <ThemeProvider>
      <RouterProvider router={router} />
    </ThemeProvider>
  );
}

export default App;

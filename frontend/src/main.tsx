import "@/fonts";
import "@/styles/index.css";

import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { createBrowserRouter, RouterProvider } from "react-router";

import { applyThemePreference, storedThemePreference } from "@/lib/theme";
import { NotFound } from "@/routes/NotFound";

// Applied before the first render so a stored theme doesn't flash the OS one first.
applyThemePreference(storedThemePreference());

const router = createBrowserRouter([{ path: "*", element: <NotFound /> }]);

const root = document.getElementById("root");
if (!root) throw new Error("index.html is missing #root");
createRoot(root).render(
  <StrictMode>
    <RouterProvider router={router} />
  </StrictMode>,
);

import "@/fonts";
import "@/styles/index.css";

import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { MemoryRouter } from "react-router";

import { applyThemePreference, storedThemePreference } from "@/lib/theme";
import { Specimen } from "@/specimen/Specimen";

applyThemePreference(storedThemePreference());

const root = document.getElementById("root");
if (!root) throw new Error("specimen.html is missing #root");
createRoot(root).render(
  <StrictMode>
    <MemoryRouter>
      <Specimen />
    </MemoryRouter>
  </StrictMode>,
);

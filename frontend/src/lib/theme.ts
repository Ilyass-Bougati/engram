import { useEffect, useState } from "react";

export type ThemePreference = "light" | "dark" | "system";

const STORAGE_KEY = "engram-theme";

function isThemePreference(value: string | null): value is ThemePreference {
  return value === "light" || value === "dark" || value === "system";
}

export function storedThemePreference(): ThemePreference {
  // Storage can throw in private windows or with site data blocked; fall back to the OS.
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    return isThemePreference(stored) ? stored : "system";
  } catch {
    return "system";
  }
}

export function applyThemePreference(preference: ThemePreference): void {
  const root = document.documentElement;
  if (preference === "system") {
    delete root.dataset.theme;
  } else {
    root.dataset.theme = preference;
  }
}

export function useThemePreference(): [ThemePreference, (next: ThemePreference) => void] {
  const [preference, setPreference] = useState(storedThemePreference);
  useEffect(() => {
    applyThemePreference(preference);
    try {
      localStorage.setItem(STORAGE_KEY, preference);
    } catch {
      // Not persisted this time; the choice still applies until the page reloads.
    }
  }, [preference]);
  return [preference, setPreference];
}

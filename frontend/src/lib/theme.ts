import { useSyncExternalStore } from "react";

export type ThemePreference = "light" | "dark" | "system";

export const THEME_OPTIONS: { value: ThemePreference; label: string }[] = [
  { value: "system", label: "Match system" },
  { value: "light", label: "Light" },
  { value: "dark", label: "Dark" },
];

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

// One shared value, so the user menu and the settings page stay in step.
let current = storedThemePreference();
const listeners = new Set<() => void>();

function setThemePreference(next: ThemePreference): void {
  current = next;
  applyThemePreference(next);
  try {
    localStorage.setItem(STORAGE_KEY, next);
  } catch {
    // Not persisted this time; the choice still applies until the page reloads.
  }
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useThemePreference(): [ThemePreference, (next: ThemePreference) => void] {
  const preference = useSyncExternalStore(subscribe, () => current);
  return [preference, setThemePreference];
}

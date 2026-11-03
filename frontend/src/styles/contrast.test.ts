import { readFileSync } from "node:fs";

import { describe, expect, test } from "vitest";

interface Rgba {
  r: number;
  g: number;
  b: number;
  a: number;
}

type Scheme = "light" | "dark";

const css = readFileSync(new URL("./tokens.css", import.meta.url), "utf8");

function parseColor(value: string): Rgba {
  const hex = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(value);
  if (hex) {
    const [, r = "", g = "", b = ""] = hex;
    return { r: parseInt(r, 16), g: parseInt(g, 16), b: parseInt(b, 16), a: 1 };
  }
  const rgb = /^rgb\((\d+) (\d+) (\d+)(?: \/ ([\d.]+))?\)$/.exec(value);
  if (rgb) {
    const [, r = "", g = "", b = "", a] = rgb;
    return { r: Number(r), g: Number(g), b: Number(b), a: a === undefined ? 1 : Number(a) };
  }
  throw new Error(`tokens.css: can't parse color ${value}`);
}

function token(name: string, scheme: Scheme): Rgba {
  const match = new RegExp(`--${name}: light-dark\\((.+?), (.+?)\\);`).exec(css);
  if (!match) throw new Error(`tokens.css: no light-dark() value for --${name}`);
  const [, light = "", dark = ""] = match;
  return parseColor(scheme === "light" ? light : dark);
}

function over(top: Rgba, bottom: Rgba): Rgba {
  const mix = (front: number, back: number) => front * top.a + back * (1 - top.a);
  return { r: mix(top.r, bottom.r), g: mix(top.g, bottom.g), b: mix(top.b, bottom.b), a: 1 };
}

function luminance({ r, g, b }: Rgba): number {
  const channel = (value: number) => {
    const c = value / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

function contrast(foreground: Rgba, background: Rgba): number {
  const solidForeground = over(foreground, background);
  const [lighter, darker] = [luminance(solidForeground), luminance(background)].sort(
    (x, y) => y - x,
  );
  return ((lighter ?? 0) + 0.05) / ((darker ?? 0) + 0.05);
}

// Glass is checked over everything that can end up behind it: the page, solid surfaces, and
// text in the ink colors scrolling under the top bar (the worst case, since blur is ignored).
function glassBackdrops(scheme: Scheme): Rgba[] {
  const page = token("paper-top", scheme);
  const behind = ["paper-top", "paper-bottom", "surface", "ink", "ink-muted"].map((name) =>
    over(token(name, scheme), page),
  );
  return behind.map((backdrop) => over(token("glass-fill", scheme), backdrop));
}

function solid(name: string, scheme: Scheme): Rgba[] {
  return [token(name, scheme)];
}

const TEXT = 4.5;
const UI = 3;

const checks: {
  label: string;
  foreground: string;
  backgrounds: (s: Scheme) => Rgba[];
  min: number;
}[] = [];
for (const text of ["ink", "ink-muted"]) {
  for (const surface of ["paper-top", "paper-bottom", "surface", "surface-sunken", "pine-soft"]) {
    checks.push({
      label: `${text} on ${surface}`,
      foreground: text,
      backgrounds: (s) => solid(surface, s),
      min: TEXT,
    });
  }
  checks.push({
    label: `${text} on glass`,
    foreground: text,
    backgrounds: glassBackdrops,
    min: TEXT,
  });
}
for (const rating of ["rating-again", "rating-hard", "rating-good", "rating-easy", "danger"]) {
  checks.push({
    label: `${rating} on surface`,
    foreground: rating,
    backgrounds: (s) => solid("surface", s),
    min: TEXT,
  });
  checks.push({
    label: `${rating} on glass`,
    foreground: rating,
    backgrounds: glassBackdrops,
    min: TEXT,
  });
}
checks.push({
  label: "on-pine on pine",
  foreground: "on-pine",
  backgrounds: (s) => solid("pine", s),
  min: TEXT,
});
checks.push({
  label: "on-danger on danger",
  foreground: "on-danger",
  backgrounds: (s) => solid("danger", s),
  min: TEXT,
});
for (const surface of ["paper-top", "paper-bottom", "surface"]) {
  checks.push({
    label: `line-strong on ${surface}`,
    foreground: "line-strong",
    backgrounds: (s) => solid(surface, s),
    min: UI,
  });
  checks.push({
    label: `focus on ${surface}`,
    foreground: "focus",
    backgrounds: (s) => solid(surface, s),
    min: UI,
  });
}
checks.push({ label: "focus on glass", foreground: "focus", backgrounds: glassBackdrops, min: UI });

describe.each(["light", "dark"] as const)("%s theme", (scheme) => {
  test.each(checks)("$label", ({ foreground, backgrounds, min }) => {
    const worst = Math.min(
      ...backgrounds(scheme).map((bg) => contrast(token(foreground, scheme), bg)),
    );
    expect(worst).toBeGreaterThanOrEqual(min);
  });
});

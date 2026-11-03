import type { HighlighterCore, ThemedToken } from "shiki/core";

// A fixed list, each grammar fetched only when a card first uses it. Shiki's full bundle
// would add megabytes for languages nobody writes on a flashcard.
const GRAMMARS = {
  bash: () => import("shiki/langs/bash.mjs"),
  c: () => import("shiki/langs/c.mjs"),
  cpp: () => import("shiki/langs/cpp.mjs"),
  css: () => import("shiki/langs/css.mjs"),
  diff: () => import("shiki/langs/diff.mjs"),
  go: () => import("shiki/langs/go.mjs"),
  html: () => import("shiki/langs/html.mjs"),
  java: () => import("shiki/langs/java.mjs"),
  javascript: () => import("shiki/langs/javascript.mjs"),
  json: () => import("shiki/langs/json.mjs"),
  jsx: () => import("shiki/langs/jsx.mjs"),
  python: () => import("shiki/langs/python.mjs"),
  rust: () => import("shiki/langs/rust.mjs"),
  sql: () => import("shiki/langs/sql.mjs"),
  tsx: () => import("shiki/langs/tsx.mjs"),
  typescript: () => import("shiki/langs/typescript.mjs"),
  yaml: () => import("shiki/langs/yaml.mjs"),
};

type Language = keyof typeof GRAMMARS;

const ALIASES: Record<string, Language> = {
  "c++": "cpp",
  golang: "go",
  js: "javascript",
  py: "python",
  rs: "rust",
  sh: "bash",
  shell: "bash",
  ts: "typescript",
  yml: "yaml",
  zsh: "bash",
};

function resolveLanguage(name: string): Language | null {
  const lower = name.toLowerCase();
  if (lower in GRAMMARS) return lower as Language;
  return ALIASES[lower] ?? null;
}

let highlighter: Promise<HighlighterCore> | null = null;

function loadHighlighter(): Promise<HighlighterCore> {
  // Colors come from --code-* in tokens.css, so code follows the light/dark theme and uses
  // only text colors whose contrast the token tests check. The JavaScript regex engine avoids
  // shipping and compiling Oniguruma's WebAssembly.
  highlighter ??= Promise.all([import("shiki/core"), import("shiki/engine/javascript")]).then(
    ([core, engine]) =>
      core.createHighlighterCore({
        themes: [core.createCssVariablesTheme({ name: "engram", variablePrefix: "--code-" })],
        langs: [],
        engine: engine.createJavaScriptRegexEngine(),
      }),
  );
  return highlighter;
}

export async function highlight(
  code: string,
  languageName: string,
): Promise<ThemedToken[][] | null> {
  const language = resolveLanguage(languageName);
  if (language === null) return null;
  const core = await loadHighlighter();
  if (!core.getLoadedLanguages().includes(language)) {
    await core.loadLanguage(GRAMMARS[language]());
  }
  return core.codeToTokensBase(code, { lang: language, theme: "engram" });
}

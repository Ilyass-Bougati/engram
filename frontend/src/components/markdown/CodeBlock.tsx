import { Fragment, useEffect, useState } from "react";
import type { ThemedToken } from "shiki/core";

import { highlight } from "@/components/markdown/highlight";

interface Highlighted {
  code: string;
  language: string;
  lines: ThemedToken[][];
}

// Renders plain text at once and swaps in colored tokens when the grammar has loaded. Tokens
// become React elements, never an HTML string, so nothing bypasses the sanitized tree.
export function CodeBlock({ code, language }: { code: string; language: string }) {
  const [highlighted, setHighlighted] = useState<Highlighted | null>(null);

  useEffect(() => {
    let current = true;
    void highlight(code, language).then((lines) => {
      if (current && lines) setHighlighted({ code, language, lines });
    });
    return () => {
      current = false;
    };
  }, [code, language]);

  const lines =
    highlighted?.code === code && highlighted.language === language ? highlighted.lines : null;

  return (
    <pre className="overflow-x-auto rounded-md border border-border bg-card px-4 py-3 font-mono text-sm leading-relaxed">
      <code>
        {lines
          ? lines.map((line, lineIndex) => (
              <Fragment key={lineIndex}>
                {line.map((token, tokenIndex) => (
                  <span key={tokenIndex} style={{ color: token.color }}>
                    {token.content}
                  </span>
                ))}
                {lineIndex < lines.length - 1 && "\n"}
              </Fragment>
            ))
          : code}
      </code>
    </pre>
  );
}

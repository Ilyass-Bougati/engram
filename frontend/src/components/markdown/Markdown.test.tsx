import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test } from "vitest";

import { Markdown } from "@/components/markdown/Markdown";

function render(text: string): string {
  return renderToStaticMarkup(<Markdown>{text}</Markdown>);
}

const HOSTILE_CARD = [
  "Before <script>alert('script')</script> after",
  '<img src="x" onerror="alert(\'img\')">',
  "[click me](javascript:alert('link'))",
  "[encoded](JaVaScRiPt:alert('mixed-case'))",
  "![pixel](javascript:alert('image'))",
  "<a href=\"javascript:alert('raw link')\">raw</a>",
  '<iframe src="https://example.com"></iframe>',
  "$\\href{javascript:alert('katex')}{math link}$",
  "$\\htmlId{x}{y}$ $\\url{javascript:alert('url')}$",
  "[data](data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==)",
].join("\n\n");

describe("card Markdown", () => {
  test("drops scripts, event handlers and script URLs", () => {
    const html = render(HOSTILE_CARD);

    expect(html).not.toMatch(/<script/i);
    expect(html).not.toMatch(/<iframe/i);
    // The Markdown image survives as a bare <img alt="pixel">; its script URL does not.
    expect(html).not.toMatch(/<img[^>]*\ssrc=/i);
    expect(html).not.toMatch(/\son[a-z]+\s*=/i);
    expect(html).not.toMatch(/(href|src)\s*=\s*"\s*(javascript|data):/i);
    expect(html).not.toMatch(/\sid="x"/);
  });

  test("keeps the surrounding text, so the test above isn't passing on empty output", () => {
    const html = render(HOSTILE_CARD);

    expect(html).toContain("Before");
    expect(html).toContain("after");
    expect(html).toContain("click me");
  });

  test("renders ordinary Markdown, math and safe links", () => {
    const html = render(
      "**bold** and `code`\n\n$a^2$\n\n[docs](https://example.com/page)\n\n| a | b |\n|---|---|\n| 1 | 2 |",
    );

    expect(html).toContain("<strong>bold</strong>");
    expect(html).toContain("<code>code</code>");
    expect(html).toMatch(/class="katex"/);
    expect(html).toMatch(
      /<a href="https:\/\/example.com\/page"[^>]*rel="noopener noreferrer nofollow"/,
    );
    expect(html).toContain("<table>");
  });
});

import "katex/dist/katex.min.css";

import ReactMarkdown, { type Components, type ExtraProps } from "react-markdown";
import rehypeKatex from "rehype-katex";
import rehypeSanitize, { defaultSchema, type Options as SanitizeSchema } from "rehype-sanitize";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";

import { CodeBlock } from "@/components/markdown/CodeBlock";
import { cn } from "@/lib/cn";

// Card text is written by one user and shown to others, so it's untrusted. Raw HTML is never
// parsed (skipHtml), and the tree is sanitized against an explicit allowlist before KaTeX
// runs. KaTeX comes after sanitizing so its own markup survives, with trust: false so
// \href, \url and \includegraphics can't produce links or requests.
const sanitizeSchema: SanitizeSchema = {
  ...defaultSchema,
  attributes: {
    ...defaultSchema.attributes,
    // Only the classes the math and code steps after sanitizing look for.
    code: [["className", /^language-./, "math-inline", "math-display"]],
  },
  protocols: {
    ...defaultSchema.protocols,
    href: ["http", "https", "mailto"],
    src: ["http", "https"],
  },
};

type HastElement = NonNullable<ExtraProps["node"]>;
type HastChild = HastElement["children"][number];

function textOf(node: HastElement | HastChild): string {
  if (node.type === "text") return node.value;
  if (node.type === "element") return node.children.map(textOf).join("");
  return "";
}

const components: Components = {
  // Links open in a new tab so following one doesn't end a review session.
  a: ({ href, title, children }) => (
    <a href={href} title={title} target="_blank" rel="noopener noreferrer nofollow">
      {children}
    </a>
  ),
  pre: ({ node, children }) => {
    const code = node?.children[0];
    if (code?.type !== "element" || code.tagName !== "code") return <pre>{children}</pre>;
    const classes = code.properties.className;
    const languageClass = Array.isArray(classes)
      ? classes.find(
          (name): name is string => typeof name === "string" && name.startsWith("language-"),
        )
      : undefined;
    return (
      <CodeBlock
        code={textOf(code).replace(/\n$/, "")}
        language={languageClass?.slice("language-".length) ?? ""}
      />
    );
  },
};

const lineComponents: Components = { ...components, a: ({ children }) => <span>{children}</span> };

export function Markdown({
  children,
  className,
  line = false,
}: {
  children: string;
  className?: string;
  // One line inside something already clickable (a list row): no links, clipped to fit.
  line?: boolean;
}) {
  return (
    <div className={cn("markdown", line && "markdown-line", className)}>
      <ReactMarkdown
        skipHtml
        remarkPlugins={[remarkGfm, remarkMath]}
        rehypePlugins={[
          [rehypeSanitize, sanitizeSchema],
          [rehypeKatex, { trust: false, strict: "ignore" }],
        ]}
        components={line ? lineComponents : components}
      >
        {children}
      </ReactMarkdown>
    </div>
  );
}

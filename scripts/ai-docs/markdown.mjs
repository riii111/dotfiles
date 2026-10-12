import markdown from "@textlint/textlint-plugin-markdown";
import { remark } from "remark";
import gfm from "remark-gfm";

const processor = new (markdown.default ?? markdown).Processor().processor(
  ".md",
);

// Prettier starts a multi-line footnote definition on the next line.
// Keep its first line after the label, as single-line definitions are.
export function joinFootnoteLabels(text) {
  const newline = text.includes("\r\n") ? "\r\n" : "\n";
  const lines = text.split(newline);
  const starts = [];

  (function collect(node) {
    if (node.type === "footnoteDefinition")
      starts.push(node.position.start.line - 1);
    for (const child of node.children ?? []) collect(child);
  })(remark().use(gfm).parse(text));

  for (const index of starts.sort((a, b) => b - a)) {
    const label = lines[index].match(/^([ \t]*)\[\^[^\]]+\]:$/u);
    const body = lines[index + 1];
    if (label && body?.startsWith(`${label[1]}    `) && body.trim()) {
      lines.splice(index, 2, `${lines[index]} ${body.trimStart()}`);
    }
  }
  return lines.join(newline);
}

export function semanticTree(source) {
  function clean(node) {
    if (Array.isArray(node)) return node.map(clean);
    if (!node || typeof node !== "object") return node;

    return Object.fromEntries(
      Object.entries(node)
        .filter(([key]) => !["loc", "range", "raw"].includes(key))
        .map(([key, value]) => [
          key,
          key === "value" && node.type === "Str"
            ? value.replace(/\s+/gu, "")
            : clean(value),
        ]),
    );
  }

  return clean(processor.preProcess(source));
}

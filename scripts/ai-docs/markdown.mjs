import markdown from "@textlint/textlint-plugin-markdown";

const processor = new (markdown.default ?? markdown).Processor().processor(
  ".md",
);

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

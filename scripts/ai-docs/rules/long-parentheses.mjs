import { hasJapanese, paragraphs } from "../prose.mjs";

export default function reporter(context, options = {}) {
  const max = options.maxLength ?? 40;
  return paragraphs(context, (node, text) => {
    const stack = [];
    for (let i = 0; i < text.length; i++) {
      if (text[i] === "（" || text[i] === "(")
        stack.push({ start: i, close: text[i] === "（" ? "）" : ")" });
      if (text[i] === stack.at(-1)?.close) {
        const { start } = stack.pop();
        const content = text.slice(start + 1, i);
        if (hasJapanese(content) && [...content.trim()].length > max) {
          context.report(
            node,
            new context.RuleError(
              `括弧内が${max}字を超えている。条件や例を本文に分けられないか確認する。`,
              { padding: context.locator.at(start) },
            ),
          );
        }
      }
    }
  });
}

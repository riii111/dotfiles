export function prose(context, node, { skipLinks = false } = {}) {
  const source = context.getSource(node);
  const chars = source.split("").map((char) => (/\s/u.test(char) ? char : " "));
  function copy(child) {
    if (skipLinks && child.type === context.Syntax.Link) return;
    const start = child.range[0] - node.range[0];
    if (child.type === context.Syntax.Str) {
      const raw = context.getSource(child);
      for (let i = 0; i < raw.length; i++) chars[start + i] = raw[i];
    } else if (child.type === context.Syntax.Code) {
      // Code contributes to length, but its punctuation must not split prose.
      const raw = context.getSource(child);
      const ticks = raw.match(/^`+/u)?.[0].length ?? 0;
      for (let i = ticks; i < raw.length - ticks; i++) {
        chars[start + i] = /\s/u.test(raw[i]) ? raw[i] : "x";
      }
    } else {
      for (const nested of child.children ?? []) copy(nested);
    }
  }
  for (const child of node.children ?? []) copy(child);
  return chars.join("");
}

export function paragraphs(context, inspect, options) {
  let quoted = 0;
  return {
    [context.Syntax.BlockQuote]() {
      quoted++;
    },
    [`${context.Syntax.BlockQuote}:exit`]() {
      quoted--;
    },
    [context.Syntax.Paragraph](node) {
      if (!quoted) inspect(node, prose(context, node, options));
    },
  };
}

export const hasJapanese = (text) =>
  /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]/u.test(text);

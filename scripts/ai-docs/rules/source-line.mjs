import { split } from "sentence-splitter";
import { hasJapanese, paragraphs } from "../prose.mjs";

function reporter(context) {
  const { RuleError, report, fixer, getSource } = context;
  // A footnote is one aside, so its sentences may stay on one line.
  let footnotes = 0;
  const handlers = paragraphs(context, (node, text) => {
    if (footnotes) return;
    let offset = 0;
    const raw = getSource(node);
    const ancestors = [];
    const openers = [];
    const openable = new Set([
      context.Syntax.Code,
      context.Syntax.Strong,
      context.Syntax.Emphasis,
      context.Syntax.Link,
      context.Syntax.Image,
    ]);

    function collect(child) {
      if (child.type !== context.Syntax.Str) ancestors.push(child.range);
      if (openable.has(child.type)) openers.push(child.range[0]);
      for (const nested of child.children ?? []) collect(nested);
    }

    for (const child of node.children ?? []) collect(child);

    for (const line of text.split("\n")) {
      if (hasJapanese(line)) {
        const sentences = split(line).filter(
          (part) => part.type === "Sentence" && part.raw.trim(),
        );

        if (sentences.length > 1) {
          const next = sentences[1];
          const boundary = offset + sentences[0].range[1];
          const nextStart = offset + next.range[0];
          // Delimiters of inline markup that opens the next sentence are blank
          // in the prose text. HTML and footnote references must stay in place.
          const gap = raw.slice(boundary, nextStart).match(/^([ \t]*)(\S*)$/u);
          const absolute = node.range[0] + boundary;
          const insideMarkup = ancestors.some(
            ([start, end]) => start < absolute && absolute < end,
          );
          const opensNext =
            gap !== null &&
            (gap[2] === "" || openers.includes(absolute + gap[1].length));

          // A sentence that starts with block syntax would become a heading,
          // list, quote, or thematic break at the start of a line.
          const blockLike =
            gap !== null &&
            /^(?:#{1,6}(?:[ \t]|$)|>|`{3,}|~{3,}|[-+*](?:[ \t]|$)|\d+[.)](?:[ \t]|$)|(?:[-*_][ \t]*){3,}$|=+[ \t]*$)/u.test(
              raw.slice(boundary + gap[1].length).split("\n")[0],
            );

          const before = raw.slice(0, boundary);
          const fixable =
            !insideMarkup &&
            opensNext &&
            !blockLike &&
            /[。！？!?]$/u.test(before);

          const sourceLine =
            node.loc.start.line + raw.slice(0, offset).split("\n").length - 1;
          const fullLine = context.getSource().split("\n")[sourceLine - 1];
          const prefix = fullLine.match(
            /^(?:[ \t]*)(?:(?:[-+*]|\d+[.)])\s+)?(?:\[[ xX]\]\s+)?/u,
          )[0];
          const indent = " ".repeat(prefix.length);
          const newline = context.getSource().includes("\r\n") ? "\r\n" : "\n";

          report(
            node,
            new RuleError("1行に1文だけを書く。", {
              padding: context.locator.at(nextStart),
              fix: fixable
                ? fixer.replaceTextRange(
                    [boundary, boundary + gap[1].length],
                    `${newline}${indent}`,
                  )
                : undefined,
            }),
          );
        }
      }
      offset += line.length + 1;
    }
  });
  return {
    ...handlers,
    footnoteDefinition() {
      footnotes++;
    },
    "footnoteDefinition:exit"() {
      footnotes--;
    },
  };
}

export default { linter: reporter, fixer: reporter };

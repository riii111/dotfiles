import { split } from "sentence-splitter";
import { hasJapanese, paragraphs } from "../prose.mjs";

function reporter(context, options = {}) {
  const { RuleError, report, fixer, getSource } = context;
  const maxSupplementLength = options.maxSupplementLength ?? 20;
  return paragraphs(context, (node, text) => {
    let offset = 0;
    const raw = getSource(node);
    const ancestors = [];

    function collect(child) {
      if (child.type !== context.Syntax.Str) ancestors.push(child.range);
      for (const nested of child.children ?? []) collect(nested);
    }

    for (const child of node.children ?? []) collect(child);

    for (const line of text.split("\n")) {
      if (hasJapanese(line)) {
        const sentences = split(line).filter(
          (part) => part.type === "Sentence" && part.raw.trim(),
        );

        if (
          sentences.length > 2 ||
          (sentences.length === 2 &&
            [...sentences[1].raw.trim()].length > maxSupplementLength)
        ) {
          const nextIndex =
            [...sentences[1].raw.trim()].length > maxSupplementLength ? 1 : 2;
          const next = sentences[nextIndex];
          const boundary = offset + sentences[nextIndex - 1].range[1];
          const nextStart = offset + next.range[0];
          const gap = raw.slice(boundary, nextStart);
          const absolute = node.range[0] + boundary;
          const insideMarkup = ancestors.some(
            ([start, end]) => start < absolute && absolute < end,
          );

          const before = raw.slice(0, boundary);
          const fixable =
            !insideMarkup &&
            /^[ \t]*$/u.test(gap) &&
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
            new RuleError(
              `1行は2文まで、2文目は${maxSupplementLength}字以内にする。補足かどうかは書き手が判断する。`,
              {
                padding: context.locator.at(nextStart),
                fix: fixable
                  ? fixer.replaceTextRange(
                      [boundary, nextStart],
                      `${newline}${indent}`,
                    )
                  : undefined,
              },
            ),
          );
        }
      }
      offset += line.length + 1;
    }
  });
}

export default { linter: reporter, fixer: reporter };

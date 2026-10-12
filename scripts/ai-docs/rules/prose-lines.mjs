import path from "node:path";

export default function reporter(context, options = {}) {
  const { Syntax, RuleError, report, getFilePath } = context;
  const lines = new Set();
  return {
    [Syntax.Paragraph](node) {
      for (let line = node.loc.start.line; line <= node.loc.end.line; line++)
        lines.add(line);
    },
    [`${Syntax.Document}:exit`](node) {
      const max =
        path.basename(getFilePath() ?? "") === "SKILL.md"
          ? (options.skillMax ?? 80)
          : (options.max ?? 100);
      if (lines.size > max) {
        report(
          node,
          new RuleError(
            `文章が${lines.size}行あり、${max}行を超えている。内容を見直すか、ファイルを分けられないか確認する。`,
          ),
        );
      }
    },
  };
}

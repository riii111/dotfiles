import { paragraphs } from "../prose.mjs";

export default function reporter(context) {
  return paragraphs(
    context,
    (node, text) => {
      let offset = 0;
      for (const line of text.split("\n")) {
        const labels = [
          ...line.matchAll(
            /(?:^|[\s、。；;])([\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}ー]{1,12})[：:]/gu,
          ),
        ];
        if (labels.length >= 2) {
          context.report(
            node,
            new context.RuleError(
              "1行にラベルを並べず、文や箇条書きに分ける。",
              { padding: context.locator.at(offset + labels[1].index) },
            ),
          );
        }
        offset += line.length + 1;
      }
    },
    { skipLinks: true },
  );
}

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";
import { TextlintKernelDescriptor } from "@textlint/kernel";
import markdown from "@textlint/textlint-plugin-markdown";
import * as prettier from "prettier";
import { createLinter } from "textlint";
import { joinFootnoteLabels, semanticTree } from "./markdown.mjs";
import rules from "./rules.mjs";

export const toolDir = fileURLToPath(new URL(".", import.meta.url));
export const repoRoot = fileURLToPath(new URL("../../", import.meta.url));

export function makeLinter(selectedRules = rules) {
  const descriptor = new TextlintKernelDescriptor({
    rules: selectedRules,
    plugins: [
      {
        pluginId: "markdown",
        plugin: markdown.default ?? markdown,
        options: true,
      },
    ],
    filterRules: [],
  });
  return createLinter({ descriptor, cwd: repoRoot });
}

export async function formatText(source, filePath) {
  const linter = makeLinter(
    rules.filter((rule) => rule.ruleId === "source-line"),
  );
  let output = source;
  for (;;) {
    const fixed = await linter.fixText(output, filePath);
    if (fixed.output === output) break;
    output = fixed.output;
  }

  const options = JSON.parse(await readFile(`${toolDir}prettier.json`, "utf8"));
  const formatted = joinFootnoteLabels(
    await prettier.format(output, {
      ...options,
      parser: "markdown",
    }),
  );

  if (!isDeepStrictEqual(semanticTree(source), semanticTree(formatted))) {
    throw new Error(
      `Markdownの構造や内容が変わるため整形を中止しました: ${filePath}`,
    );
  }

  return formatted;
}

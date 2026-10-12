import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { formatText, makeLinter } from "../linter.mjs";
import { semanticTree } from "../markdown.mjs";
import rules from "../rules.mjs";

describe("source-line", () => {
  for (const { name, source } of [
    {
      name: "a single sentence",
      source: "OKが効くのは新規起動だけとする。",
    },
    {
      name: "sentence marks inside quotes",
      source: "引用「最初。次。最後。」を使う。",
    },
    {
      name: "sentence marks inside code",
      source: "`a.b。c。d。`を使う。",
    },
    {
      name: "English-only sentences",
      source: "Use the first option. Use another option. Try the last option.",
    },
  ]) {
    test(`accepts ${name} without a warning`, async () => {
      const result = await lintRule("source-line", source);

      assert.deepEqual(result.messages, []);
    });
  }

  test("moves every sentence after the first to its own line", async () => {
    const source = "最初の決まり。短い補足。三つ目の決まり。";

    const result = await lintRule("source-line", source);
    const output = await formatText(source, "example.md");

    assert.equal(result.messages.length, 1);
    assert.equal(output, "最初の決まり。\n短い補足。\n三つ目の決まり。\n");
  });

  const long = "短い補足。";
  for (const { name, source, expected } of [
    {
      name: "a numbered list",
      source: `1. 最初の決まり。${long}\n`,
      expected: `1. 最初の決まり。\n   ${long}\n`,
    },
    {
      name: "a CRLF task list",
      source: `- [ ] 最初の決まり。${long}\r\n`,
      expected: `- [ ] 最初の決まり。\r\n      ${long}\r\n`,
    },
    {
      name: "a nested list",
      source: `- 親\n  - 子の決まり。${long}\n`,
      expected: `- 親\n  - 子の決まり。\n    ${long}\n`,
    },
    {
      name: "a sentence that starts with inline code",
      source: `最初の決まり。\`code\`${long}\n`,
      expected: `最初の決まり。\n\`code\`${long}\n`,
    },
    {
      name: "a sentence that starts with bold text",
      source: `- 最初の決まり。 **太字**${long}\n`,
      expected: `- 最初の決まり。\n  **太字**${long}\n`,
    },
    {
      name: "a sentence that starts with a link",
      source: `最初の決まり。[リンク](https://example.com)${long}\n`,
      expected: `最初の決まり。\n[リンク](https://example.com)${long}\n`,
    },
  ]) {
    test(`preserves the continuation prefix when splitting ${name}`, async () => {
      const output = await fixSourceLines(source);

      assert.equal(output, expected);
    });
  }

  test("locates a warning on the actual continuation line", async () => {
    const result = await lintRule(
      "source-line",
      "最初の行。\n次の行。補足。三つ目。\n",
    );

    assert.equal(result.messages.length, 1);
    assert.equal(result.messages[0].loc.start.line, 2);
  });

  for (const { name, source } of [
    { name: "bold text", source: "**最初。補足。三つ目。**" },
    {
      name: "a link label",
      source: "[最初。補足。三つ目。](https://example.com)",
    },
  ]) {
    test(`warns without splitting inside ${name}`, async () => {
      const result = await lintRule("source-line", source);
      const output = await fixSourceLines(source);

      assert.equal(result.messages.length, 1);
      assert.equal(output, source);
    });
  }

  for (const { name, source } of [
    { name: "a heading marker", source: "最初。# 見出しに見える文。" },
    { name: "a list marker", source: "これは文。- 開く。" },
    { name: "an ordered list marker", source: "値は2。3. 次の値。" },
    { name: "a quote marker", source: "これは文。> 引用に見える文。" },
    { name: "a thematic break", source: "これは文。---" },
    { name: "block HTML", source: `最初の決まり。<div>${long}` },
    {
      name: "an inline HTML closing tag",
      source: `<span>最初の決まり。</span>${long}`,
    },
    {
      name: "a footnote reference",
      source: `最初の決まり。[^1]${long}\n\n[^1]: 注。`,
    },
  ]) {
    test(`warns without moving ${name} to the next line`, async () => {
      const result = await lintRule("source-line", source);
      const output = await fixSourceLines(source);

      assert.equal(result.messages.length, 1);
      assert.equal(output, source);
    });
  }
});

for (const ruleId of ["source-line", "long-parentheses"]) {
  describe(`${ruleId} outside prose`, () => {
    for (const { name, source } of excludedExamples()) {
      test(`ignores ${name}`, async () => {
        const result = await lintRule(ruleId, source);

        assert.deepEqual(result.messages, []);
      });
    }
  });
}

describe("long-parentheses", () => {
  for (const { name, source, expected } of [
    {
      name: "40 Japanese characters",
      source: `条件（${"あ".repeat(40)}）`,
      expected: 0,
    },
    {
      name: "41 Japanese characters",
      source: `条件（${"あ".repeat(41)}）`,
      expected: 1,
    },
    {
      name: "two long nested parentheses",
      source: `条件（短い（${"あ".repeat(41)}）補足）`,
      expected: 2,
    },
    {
      name: "English-only parentheses",
      source: `Example (${"word ".repeat(20)})`,
      expected: 0,
    },
  ]) {
    test(`reports ${expected} ${expected === 1 ? "warning" : "warnings"} for ${name}`, async () => {
      const result = await lintRule("long-parentheses", source);

      assert.equal(result.messages.length, expected);
    });
  }
});

describe("prose-lines", () => {
  const prose = (count) =>
    Array.from({ length: count }, () => "文。").join("\n");
  for (const { name, file, source, expected } of [
    {
      name: "80 lines in SKILL.md",
      file: "SKILL.md",
      source: prose(80),
      expected: 0,
    },
    {
      name: "81 lines in SKILL.md",
      file: "SKILL.md",
      source: prose(81),
      expected: 1,
    },
    {
      name: "100 lines in a reference",
      file: "guide.md",
      source: prose(100),
      expected: 0,
    },
    {
      name: "101 lines in a reference",
      file: "guide.md",
      source: prose(101),
      expected: 1,
    },
    {
      name: "code blocks, tables, and HTML in SKILL.md",
      file: "SKILL.md",
      source: `${prose(80)}\n\n\`\`\`text\n${prose(10)}\n\`\`\`\n\n| 例 |\n| --- |\n| 文。 |\n\n<div>\n${prose(10)}\n</div>\n`,
      expected: 0,
    },
  ]) {
    test(`reports ${expected} ${expected === 1 ? "warning" : "warnings"} for ${name}`, async () => {
      const result = await lintRule("prose-lines", source, file);

      assert.equal(result.messages.length, expected);
    });
  }
});

describe("formatText", () => {
  test("adds line breaks without changing Markdown structure or code contents", async () => {
    const source = formattingExample();

    const output = await formatText(source, "example.md");

    assert.match(output, /最初の決まり。\n {2}補足。\n {2}三つ目の決まり。/u);
    assert.match(output, /\{"keep": {4}"spacing"\}/u);
    assert.deepEqual(semanticTree(output), semanticTree(source));
  });

  test("produces no further changes after an initial formatting pass", async () => {
    const source = formattingExample();
    const formatted = await formatText(source, "example.md");
    assert.notEqual(formatted, source);

    const output = await formatText(formatted, "example.md");

    assert.equal(output, formatted);
  });

  for (const { name, source, expected } of [
    {
      name: "a footnote definition",
      source: "本文。[^1]\n\n[^1]: 脚注。追加の文。\n",
      expected: "本文。[^1]\n\n[^1]: 脚注。\n    追加の文。\n",
    },
    {
      name: "a CRLF footnote definition in a list",
      source: "- 項目。[^1]\r\n\r\n  [^1]: 脚注。追加の文。\r\n",
      expected: "- 項目。[^1]\r\n\r\n  [^1]: 脚注。\r\n      追加の文。\r\n",
    },
    {
      name: "a footnote-like line in a code block",
      source: "```md\n[^1]:\n    コード。\n```\n",
      expected: "```md\n[^1]:\n    コード。\n```\n",
    },
  ]) {
    test(`keeps the first line after the label in ${name}`, async () => {
      const output = await formatText(source, "example.md");

      assert.equal(output, expected);
      assert.equal(await formatText(output, "example.md"), output);
    });
  }

  test("keeps a sentence that would become a heading on the same line", async () => {
    const output = await formatText("最初。補足。# 三つ目。", "example.md");

    assert.equal(output, "最初。\n補足。# 三つ目。\n");
  });
});

function ruleLinter(ruleId) {
  return makeLinter(rules.filter((rule) => rule.ruleId === ruleId));
}

function lintRule(ruleId, source, file = "example.md") {
  return ruleLinter(ruleId).lintText(source, file);
}

async function fixSourceLines(source) {
  return (await ruleLinter("source-line").fixText(source, "example.md")).output;
}

function excludedExamples() {
  const noisy = `最初の決まり。補足。三つ目。（${"長い条件".repeat(15)}）`;
  return [
    { name: "YAML frontmatter", source: `---\ndescription: ${noisy}\n---\n` },
    { name: "a fenced example", source: `\`\`\`markdown\n${noisy}\n\`\`\`\n` },
    { name: "a quoted example", source: `> ${noisy}\n` },
    { name: "a table cell", source: `| 例 |\n| --- |\n| ${noisy} |\n` },
  ];
}

function formattingExample() {
  return `---
name: example
description: 例
---

- 最初の決まり。補足。三つ目の決まり。

\`\`\`json
{"keep":    "spacing"}
\`\`\`

| 名前 | 値 |
| --- | --- |
| 例 | 1 |
`;
}

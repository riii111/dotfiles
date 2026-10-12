import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { formatText, makeLinter } from "../linter.mjs";
import { semanticTree } from "../markdown.mjs";
import rules from "../rules.mjs";

describe("source-line", () => {
  for (const { name, source } of [
    {
      name: "a short second sentence",
      source: "OKが効くのは新規起動だけとする。続行には効かない。",
    },
    {
      name: "sentence marks inside quotes",
      source: "引用「最初。次。最後。」を使う。短い補足。",
    },
    {
      name: "sentence marks inside code",
      source: "`a.b。c。d。`を使う。短い補足。",
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

  test("moves a third sentence to a new line while keeping a short supplement", async () => {
    const source = "最初の決まり。短い補足。三つ目の決まり。";

    const result = await lintRule("source-line", source);
    const output = await fixSourceLines(source);

    assert.equal(result.messages.length, 1);
    assert.equal(output, "最初の決まり。短い補足。\n三つ目の決まり。");
  });

  const long = "これは二十字を超える長い二つ目の決まりなので別の行にする。";
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
});

for (const ruleId of ["source-line", "label-list", "long-parentheses"]) {
  describe(`${ruleId} outside prose`, () => {
    for (const { name, source } of excludedExamples()) {
      test(`ignores ${name}`, async () => {
        const result = await lintRule(ruleId, source);

        assert.deepEqual(result.messages, []);
      });
    }
  });
}

describe("label-list", () => {
  for (const { name, source, expected } of [
    {
      name: "two labels on one line",
      source: "依頼：作業 変化：差分",
      expected: 1,
    },
    {
      name: "labels on separate lines",
      source: "依頼：作業\n変化：差分",
      expected: 0,
    },
    {
      name: "a colon inside a link label",
      source: "場所: [ファイル名:行番号](URL)",
      expected: 0,
    },
    {
      name: "colons inside code",
      source: "`依頼：作業 変化：差分`の形式を示す。",
      expected: 0,
    },
  ]) {
    test(`reports ${expected} ${expected === 1 ? "warning" : "warnings"} for ${name}`, async () => {
      const result = await lintRule("label-list", source);

      assert.equal(result.messages.length, expected);
    });
  }
});

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

describe("formatText", () => {
  test("adds line breaks without changing Markdown structure or code contents", async () => {
    const source = formattingExample();

    const output = await formatText(
      ruleLinter("source-line"),
      source,
      "example.md",
    );

    assert.match(output, /最初の決まり。補足。\n {2}三つ目の決まり。/u);
    assert.match(output, /\{"keep": {4}"spacing"\}/u);
    assert.deepEqual(semanticTree(output), semanticTree(source));
  });

  test("produces no further changes after an initial formatting pass", async () => {
    const linter = ruleLinter("source-line");
    const source = formattingExample();
    const formatted = await formatText(linter, source, "example.md");
    assert.notEqual(formatted, source);

    const output = await formatText(linter, formatted, "example.md");

    assert.equal(output, formatted);
  });

  test("rejects a line break that would turn prose into a heading", async () => {
    await assert.rejects(
      formatText(
        ruleLinter("source-line"),
        "最初。補足。# 三つ目。",
        "example.md",
      ),
      /構造や内容が変わる/u,
    );
  });
});

function ruleLinter(ruleId) {
  return makeLinter(rules.filter((rule) => rule.ruleId === ruleId));
}

function lintRule(ruleId, source) {
  return ruleLinter(ruleId).lintText(source, "example.md");
}

async function fixSourceLines(source) {
  return (await ruleLinter("source-line").fixText(source, "example.md")).output;
}

function excludedExamples() {
  const noisy = `依頼：作業 変化：差分。補足。三つ目。（${"長い条件".repeat(15)}）`;
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

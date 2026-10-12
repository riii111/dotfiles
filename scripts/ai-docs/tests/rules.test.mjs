import assert from "node:assert/strict";
import test from "node:test";
import { formatText, makeLinter } from "../linter.mjs";
import { semanticTree } from "../markdown.mjs";
import rules from "../rules.mjs";

const only = (id) => makeLinter(rules.filter((rule) => rule.ruleId === id));
const lint = (id, text) => only(id).lintText(text, "example.md");
const fix = async (text) =>
  (await only("source-line").fixText(text, "example.md")).output;

test("source lines allow a short supplement and count Japanese sentences outside quotes and code", async () => {
  for (const text of [
    "OKが効くのは新規起動だけとする。続行には効かない。",
    "引用「最初。次。最後。」を使う。短い補足。",
    "`a.b。c。d。`を使う。短い補足。",
    "「依頼：」「変化：」は例として示す。",
    "Use the first option. Use another option. Try the last option.",
  ])
    assert.equal((await lint("source-line", text)).messages.length, 0, text);
  const violation = "最初の決まり。短い補足。三つ目の決まり。";
  assert.equal((await lint("source-line", violation)).messages.length, 1);
  assert.equal(
    await fix(violation),
    "最初の決まり。短い補足。\n三つ目の決まり。",
  );
});

test("a long second sentence is split with list indentation and CRLF intact", async () => {
  const long = "これは二十字を超える長い二つ目の決まりなので別の行にする。";
  assert.equal(
    await fix(`1. 最初の決まり。${long}\n`),
    `1. 最初の決まり。\n   ${long}\n`,
  );
  assert.equal(
    await fix(`- [ ] 最初の決まり。${long}\r\n`),
    `- [ ] 最初の決まり。\r\n      ${long}\r\n`,
  );
  assert.equal(
    await fix(`- 親\n  - 子の決まり。${long}\n`),
    `- 親\n  - 子の決まり。\n    ${long}\n`,
  );
});

test("source-line warnings locate continuation lines and do not split inline markup", async () => {
  const result = await lint(
    "source-line",
    "最初の行。\n次の行。補足。三つ目。\n",
  );
  assert.equal(result.messages[0].line, 2);
  assert.equal(
    await fix("**最初。補足。三つ目。**"),
    "**最初。補足。三つ目。**",
  );
  assert.equal(
    await fix("[最初。補足。三つ目。](https://example.com)"),
    "[最初。補足。三つ目。](https://example.com)",
  );
});

test("custom prose checks ignore fences, frontmatter, tables and quoted examples", async () => {
  const noisy = `依頼：作業 変化：差分。補足。三つ目。（${"長い条件".repeat(15)}）`;
  const examples = [
    `---\ndescription: ${noisy}\n---\n`,
    `\`\`\`markdown\n${noisy}\n\`\`\`\n`,
    `> ${noisy}\n`,
    `| 例 |\n| --- |\n| ${noisy} |\n`,
  ];
  for (const id of ["source-line", "label-list", "long-parentheses"]) {
    for (const text of examples)
      assert.equal((await lint(id, text)).messages.length, 0, `${id}: ${text}`);
  }
});

test("labels are reported across prose but not inside code or link labels", async () => {
  assert.equal(
    (await lint("label-list", "依頼：作業 変化：差分")).messages.length,
    1,
  );
  assert.equal(
    (await lint("label-list", "依頼：作業\n変化：差分")).messages.length,
    0,
  );
  assert.equal(
    (await lint("label-list", "場所: [ファイル名:行番号](URL)")).messages
      .length,
    0,
  );
  assert.equal(
    (await lint("label-list", "`依頼：作業 変化：差分`の形式を示す。")).messages
      .length,
    0,
  );
});

test("parenthesis threshold handles nesting and ignores English parentheses", async () => {
  assert.equal(
    (await lint("long-parentheses", `条件（${"あ".repeat(40)}）`)).messages
      .length,
    0,
  );
  assert.equal(
    (await lint("long-parentheses", `条件（${"あ".repeat(41)}）`)).messages
      .length,
    1,
  );
  assert.equal(
    (await lint("long-parentheses", `条件（短い（${"あ".repeat(41)}）補足）`))
      .messages.length,
    2,
  );
  assert.equal(
    (await lint("long-parentheses", `Example (${"word ".repeat(20)})`)).messages
      .length,
    0,
  );
});

test("fmt preserves Markdown structure and code, and is idempotent", async () => {
  const source = `---\nname: example\ndescription: 例\n---\n\n- 最初の決まり。補足。三つ目の決まり。\n\n\`\`\`json\n{"keep":    "spacing"}\n\`\`\`\n\n| 名前 | 値 |\n| --- | --- |\n| 例 | 1 |\n`;
  const linter = only("source-line");
  const output = await formatText(linter, source, "example.md");
  assert.match(output, /最初の決まり。補足。\n {2}三つ目の決まり。/u);
  assert.match(output, /\{"keep": {4}"spacing"\}/u);
  assert.deepEqual(semanticTree(output), semanticTree(source));
  assert.equal(await formatText(linter, output, "example.md"), output);
});

test("fmt refuses an inserted newline that would turn prose into a heading", async () => {
  await assert.rejects(
    formatText(only("source-line"), "最初。補足。# 三つ目。", "example.md"),
    /構造や内容が変わる/u,
  );
});

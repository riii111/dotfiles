import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, test } from "node:test";
import { repoRoot, toolDir } from "../linter.mjs";

describe("lint command", () => {
  test("reports warnings successfully when strict mode is omitted", async (context) => {
    const dir = await scratch(context);
    const file = await writeMarkdown(dir, "依頼：作業 変化：差分\n");

    const result = run("lint", "--json", file);

    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(
      JSON.parse(result.stdout)[0].messages.map((message) => message.ruleId),
      ["label-list"],
    );
  });

  test("fails with the warning diagnostic when strict mode is enabled", async (context) => {
    const dir = await scratch(context);
    const file = await writeMarkdown(dir, "依頼：作業 変化：差分\n");

    const result = run("lint", "--strict", file);

    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stdout, /label-list/u);
  });

  test("reports the repeated label's exact position on a continuation line", async (context) => {
    const dir = await scratch(context);
    const file = await writeMarkdown(
      dir,
      "最初の行。\n依頼：作業 変化：差分\n",
    );

    const result = run("lint", "--json", file);

    assert.equal(result.status, 0, result.stderr);
    const [message] = JSON.parse(result.stdout)[0].messages;
    assert.deepEqual(
      {
        ruleId: message.ruleId,
        start: message.loc.start,
        line: message.line,
        column: message.column,
      },
      {
        ruleId: "label-list",
        start: { line: 2, column: 6 },
        line: 2,
        column: 6,
      },
    );

    const text = run("lint", file);
    assert.equal(text.status, 0, text.stderr);
    assert.match(text.stdout, /example\.md:2:6 label-list:/u);
  });

  test("fails when the requested Markdown file does not exist", async (context) => {
    const dir = await scratch(context);

    const result = run("lint", path.join(dir, "missing.md"));

    assert.equal(result.status, 1);
    assert.match(result.stderr, /ENOENT/u);
  });
});

describe("fmt command", () => {
  test("reports pending changes without writing in check mode", async (context) => {
    const dir = await scratch(context);
    const source = "最初の文。補足。三つ目の文。\n";
    const file = await writeMarkdown(dir, source);

    const result = run("fmt", "--check", file);

    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stdout, /1 would change/u);
    assert.equal(await readFile(file, "utf8"), source);
  });

  test("writes the formatted content and then passes check mode", async (context) => {
    const dir = await scratch(context);
    const file = await writeMarkdown(dir, "最初の文。補足。三つ目の文。\n");

    const written = run("fmt", file);

    assert.equal(written.status, 0, written.stderr);
    assert.equal(
      await readFile(file, "utf8"),
      "最初の文。補足。\n三つ目の文。\n",
    );

    const checked = run("fmt", "--check", file);
    assert.equal(checked.status, 0, checked.stderr);
  });

  test("requires an explicit Markdown file", () => {
    const result = run("fmt");

    assert.equal(result.status, 1);
    assert.match(result.stderr, /変更対象のMarkdownファイルを指定/u);
  });

  test("refuses a symlink without changing its target", async (context) => {
    const dir = await scratch(context);
    const source = "最初の文。補足。三つ目の文。\n";
    const file = await writeMarkdown(dir, source);
    const link = path.join(dir, "link.md");
    await symlink(file, link);

    const result = run("fmt", link);

    assert.equal(result.status, 1);
    assert.match(result.stderr, /通常のMarkdownファイル/u);
    assert.equal(await readFile(file, "utf8"), source);
  });
});

describe("links command", () => {
  test("accepts a Japanese heading in another file without writing", async (context) => {
    const { entry, target, source } = await linkedFiles(context);

    const result = run("links", entry, target);

    assert.equal(result.status, 0, result.stderr);
    assert.equal(await readFile(entry, "utf8"), source);
  });

  for (const { name, destination, diagnostic } of [
    {
      name: "a missing file",
      destination: "missing.md",
      diagnostic: /missing-file/u,
    },
    {
      name: "a missing Japanese heading",
      destination: "target.md#存在しない見出し",
      diagnostic: /missing-heading/u,
    },
  ]) {
    test(`rejects ${name} after a valid reference succeeds`, async (context) => {
      const { entry, target } = await linkedFiles(context);
      const valid = run("links", entry, target);
      assert.equal(valid.status, 0, valid.stderr);
      await writeFile(entry, `[参照](${destination})\n`);

      const result = run("links", entry, target);

      assert.equal(result.status, 1);
      assert.match(result.stderr, diagnostic);
    });
  }
});

function run(...args) {
  return spawnSync(process.execPath, [`${toolDir}cli.mjs`, ...args], {
    cwd: repoRoot,
    encoding: "utf8",
  });
}

async function scratch(context) {
  const dir = await mkdtemp(path.join(os.tmpdir(), "ai-doc-test-"));
  context.after(() => rm(dir, { recursive: true }));
  return dir;
}

async function writeMarkdown(dir, source, name = "example.md") {
  const file = path.join(dir, name);
  await writeFile(file, source);
  return file;
}

async function linkedFiles(context) {
  const dir = await scratch(context);
  const source = "[参照](target.md#日本語の見出し)\n";
  const entry = await writeMarkdown(dir, source, "entry.md");
  const target = await writeMarkdown(dir, "# 日本語の見出し\n", "target.md");
  return { entry, target, source };
}

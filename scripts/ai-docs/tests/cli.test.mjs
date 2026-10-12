import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import {
  cp,
  mkdir,
  mkdtemp,
  readFile,
  realpath,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, test } from "node:test";
import { repoRoot, toolDir } from "../linter.mjs";

describe("lint command", () => {
  test("limits all mode to tracked SKILL Markdown across both roots", async (context) => {
    const { checkout, files } = await skillRepository(context);

    const result = runInRepository(checkout, "lint", "--all", "--json");

    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(
      JSON.parse(result.stdout).map((entry) =>
        path.relative(checkout, entry.filePath),
      ),
      files,
    );
  });

  test("reports warnings successfully when strict mode is omitted", async (context) => {
    const dir = await scratch(context);
    const file = await writeMarkdown(dir, "最初の文。補足。三つ目の文。\n");

    const result = run("lint", "--json", file);

    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(
      JSON.parse(result.stdout)[0].messages.map((message) => message.ruleId),
      ["source-line"],
    );
  });

  test("fails with the warning diagnostic when strict mode is enabled", async (context) => {
    const dir = await scratch(context);
    const file = await writeMarkdown(dir, "最初の文。補足。三つ目の文。\n");

    const result = run("lint", "--strict", file);

    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stdout, /source-line/u);
  });

  test("reports the second sentence's exact position on a continuation line", async (context) => {
    const dir = await scratch(context);
    const file = await writeMarkdown(
      dir,
      "最初の行。\n次の行。補足。三つ目。\n",
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
        ruleId: "source-line",
        start: { line: 2, column: 5 },
        line: 2,
        column: 5,
      },
    );

    const text = run("lint", file);
    assert.equal(text.status, 0, text.stderr);
    assert.match(text.stdout, /example\.md:2:5 source-line:/u);
  });

  test("fails when the requested Markdown file does not exist", async (context) => {
    const dir = await scratch(context);

    const result = run("lint", path.join(dir, "missing.md"));

    assert.equal(result.status, 1);
    assert.match(result.stderr, /ENOENT/u);
  });
});

describe("fmt command", () => {
  test("preserves fixable redundant expressions while splitting source lines", async (context) => {
    const dir = await scratch(context);
    const file = await writeMarkdown(
      dir,
      "これは使用することができる。補足。三つ目の文。\n",
    );

    const result = run("fmt", file);

    assert.equal(result.status, 0, result.stderr);
    assert.equal(
      await readFile(file, "utf8"),
      "これは使用することができる。\n補足。\n三つ目の文。\n",
    );
  });

  test("preserves all files when a later file would change Markdown structure", async (context) => {
    const { checkout, files, source } = await skillRepository(context);
    const invalid = "- 項目\n続きの行。\n";
    await writeFile(path.join(checkout, files[1]), invalid);

    const result = runInRepository(checkout, "fmt", "--all");

    assert.equal(result.status, 1);
    assert.match(result.stderr, /構造や内容が変わる/u);
    assert.equal(await readFile(path.join(checkout, files[0]), "utf8"), source);
    assert.equal(
      await readFile(path.join(checkout, files[1]), "utf8"),
      invalid,
    );
  });

  test("checks and formats all tracked SKILL Markdown while preserving excluded files", async (context) => {
    const { checkout, files, excluded, source } =
      await skillRepository(context);

    const pending = runInRepository(checkout, "fmt", "--all", "--check");

    assert.equal(pending.status, 1, pending.stderr);
    assert.match(pending.stdout, /2 files, 2 would change/u);
    for (const file of [...files, ...excluded])
      assert.equal(await readFile(path.join(checkout, file), "utf8"), source);

    const written = runInRepository(checkout, "fmt", "--all");

    assert.equal(written.status, 0, written.stderr);
    assert.match(written.stdout, /2 files, 2 changed/u);
    for (const file of files)
      assert.equal(
        await readFile(path.join(checkout, file), "utf8"),
        "最初の文。\n補足。\n三つ目の文。\n",
      );
    for (const file of excluded)
      assert.equal(await readFile(path.join(checkout, file), "utf8"), source);

    const checked = runInRepository(checkout, "fmt", "--all", "--check");
    assert.equal(checked.status, 0, checked.stderr);
  });

  test("rejects combining all mode with an explicit file", async (context) => {
    const dir = await scratch(context);
    const source = "最初の文。補足。三つ目の文。\n";
    const file = await writeMarkdown(dir, source);

    const result = run("fmt", "--all", file);

    assert.equal(result.status, 1);
    assert.match(result.stderr, /--allとファイル指定は同時に使えません/u);
    assert.equal(await readFile(file, "utf8"), source);
  });

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
      "最初の文。\n補足。\n三つ目の文。\n",
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
  test("limits all mode to tracked SKILL Markdown across both roots", async (context) => {
    const { checkout } = await skillRepository(context);

    const result = runInRepository(checkout, "links", "--all");

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /2 files, links checked/u);
  });

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
  return runInRepository(repoRoot, ...args);
}

function runInRepository(checkout, ...args) {
  return spawnSync(
    process.execPath,
    [path.join(checkout, "scripts/ai-docs/cli.mjs"), ...args],
    {
      cwd: checkout,
      encoding: "utf8",
    },
  );
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

async function skillRepository(context) {
  const checkout = await realpath(await scratch(context));
  const fixtureToolDir = path.join(checkout, "scripts/ai-docs");
  await cp(toolDir, fixtureToolDir, {
    recursive: true,
    filter: (source) => path.basename(source) !== "node_modules",
  });
  await symlink(
    path.join(toolDir, "node_modules"),
    path.join(fixtureToolDir, "node_modules"),
    "dir",
  );

  const source = "最初の文。補足。三つ目の文。\n";
  const files = [
    "dot_claude/skills/example/notes with spaces.md",
    "dot_codex/skills/example/SKILL.md",
  ];
  const excluded = ["dot_codex/skills/example/untracked.md", "README.md"];
  for (const file of [...files, ...excluded]) {
    const destination = path.join(checkout, file);
    await mkdir(path.dirname(destination), { recursive: true });
    await writeFile(destination, source);
  }

  execFileSync("git", ["init", "--quiet", checkout]);
  execFileSync("git", ["-C", checkout, "add", "--", ...files, "README.md"]);
  return { checkout, files, excluded, source };
}

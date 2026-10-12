import assert from "node:assert/strict";
import test from "node:test";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { repoRoot, toolDir } from "../linter.mjs";

const run = (...args) =>
  spawnSync(process.execPath, [`${toolDir}cli.mjs`, ...args], {
    cwd: repoRoot,
    encoding: "utf8",
  });

test("lint warnings are advisory, strict lint fails, and JSON uses actual source positions", async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), "ai-doc-test-"));
  try {
    const file = path.join(dir, "example.md");
    await writeFile(file, "最初の行。\n依頼：作業 変化：差分\n");
    const advisory = run("lint", "--json", file);
    assert.equal(advisory.status, 0, advisory.stderr);
    const message = JSON.parse(advisory.stdout)[0].messages.find(
      (m) => m.ruleId === "label-list",
    );
    assert.equal(message.line, 2);
    assert.ok(message.column < 20);
    assert.equal(run("lint", "--strict", file).status, 1);
    assert.equal(run("lint", path.join(dir, "missing.md")).status, 1);
  } finally {
    await rm(dir, { recursive: true });
  }
});

test("fmt check is read-only, fmt requires explicit files, and symlinks are refused", async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), "ai-doc-test-"));
  try {
    const file = path.join(dir, "example.md");
    const source = "最初の文。補足。三つ目の文。\n";
    await writeFile(file, source);
    const check = run("fmt", "--check", file);
    assert.equal(check.status, 1, check.stderr);
    assert.equal(await readFile(file, "utf8"), source);
    assert.equal(run("fmt", file).status, 0);
    assert.equal(run("fmt", "--check", file).status, 0);
    assert.equal(run("fmt").status, 1);
    execFileSync("ln", ["-s", file, path.join(dir, "link.md")]);
    assert.equal(run("fmt", path.join(dir, "link.md")).status, 1);
  } finally {
    await rm(dir, { recursive: true });
  }
});

test("links check cross-file Japanese anchors and fail on missing files without writing", async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), "ai-doc-test-"));
  try {
    const entry = path.join(dir, "entry.md");
    const target = path.join(dir, "target.md");
    await writeFile(target, "# 日本語の見出し\n");
    const good = "[参照](target.md#日本語の見出し)\n";
    await writeFile(entry, good);
    const result = run("links", entry, target);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(await readFile(entry, "utf8"), good);
    await writeFile(
      entry,
      "[参照](target.md#存在しない見出し)\n[参照](missing.md)\n",
    );
    const bad = run("links", entry, target);
    assert.equal(bad.status, 1);
    assert.match(bad.stderr, /missing-file/u);
    assert.match(bad.stderr, /missing-heading/u);
  } finally {
    await rm(dir, { recursive: true });
  }
});

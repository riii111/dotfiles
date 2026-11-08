import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { TextlintKernelDescriptor } from "@textlint/kernel";
import markdown from "@textlint/textlint-plugin-markdown";
import { remark } from "remark";
import validateLinks from "remark-validate-links";
import { createLinter } from "textlint";
import { engine } from "unified-engine";

// Resolve through the consumers so nested dependencies are tested too.
const engineRequire = createRequire(import.meta.resolve("unified-engine"));
const pluginRequire = createRequire(engineRequire.resolve("load-plugin"));
const configRequire = createRequire(pluginRequire.resolve("@npmcli/config"));
const mapWorkspaces = configRequire("@npmcli/map-workspaces");
const PackageJson = configRequire("@npmcli/package-json");

async function fixture(t, files) {
  const cwd = await mkdtemp(path.join(tmpdir(), "ai-docs-deps-"));
  t.after(() => rm(cwd, { recursive: true, force: true }));
  for (const [name, content] of Object.entries(files)) {
    const file = path.join(cwd, name);
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(file, content);
  }
  return cwd;
}

function checkLinks(cwd, files) {
  return new Promise((resolve, reject) => {
    engine(
      {
        processor: remark,
        plugins: [[validateLinks, { root: cwd, repository: false }]],
        cwd,
        files,
        extensions: ["md"],
        detectConfig: false,
        detectIgnore: false,
        output: false,
        out: false,
        frail: true,
        silent: true,
      },
      (error, status, context) =>
        error ? reject(error) : resolve({ status, files: context.files }),
    );
  });
}

test("unified-engine expands globs and validates linked Markdown anchors", async (t) => {
  const cwd = await fixture(t, {
    "docs/index.md": "# Index\n\n[Guide](../guide/topic.md#details)\n",
    "guide/topic.md": "# Details\n",
    "docs/nested/other.md": "# Other\n",
    "docs/日本語.md": "# 日本語\n",
  });
  const result = await checkLinks(cwd, ["docs/**/*.md"]);
  assert.equal(result.status, 0);
  assert.deepEqual(
    result.files
      .map((file) => path.relative(cwd, path.resolve(cwd, file.path)))
      .sort(),
    ["docs/index.md", "docs/nested/other.md", "docs/日本語.md"],
  );
});

for (const destination of ["../guide/topic.md#missing", "missing.md"]) {
  test(`link validation rejects ${destination}`, async (t) => {
    const cwd = await fixture(t, {
      "docs/index.md": `# Index\n\n[Broken](${destination})\n`,
      "guide/topic.md": "# Details\n",
    });
    const result = await checkLinks(cwd, ["docs/*.md"]);
    assert.equal(result.status, 1);
    assert.ok(result.files.some((file) => file.messages.length > 0));
  });
}

test("textlint finds globbed files and respects ignore patterns", async (t) => {
  const cwd = await fixture(t, {
    "docs/a.md": "# A\n",
    "docs/nested/b.md": "# B\n",
    "docs/.hidden.md": "# Hidden\n",
    "docs/日本語.md": "# 日本語\n",
    "docs/ignored.md": "# Ignored\n",
    ".textlintignore": "docs/ignored.md\n",
  });
  const descriptor = new TextlintKernelDescriptor({
    rules: [],
    plugins: [
      {
        pluginId: "markdown",
        plugin: markdown.default ?? markdown,
        options: true,
      },
    ],
    filterRules: [],
  });
  const linter = createLinter({
    descriptor,
    cwd,
    ignoreFilePath: path.join(cwd, ".textlintignore"),
  });
  const results = await linter.lintFiles(["docs/**/*.md"]);
  assert.deepEqual(
    results.map((result) => path.relative(cwd, result.filePath)).sort(),
    ["docs/.hidden.md", "docs/a.md", "docs/nested/b.md", "docs/日本語.md"],
  );
  assert.ok(results.every((result) => result.messages.length === 0));
});

test("workspace discovery preserves braces, negation, ordering, and virtual maps", async (t) => {
  const packages = {
    "packages/a": { name: "a" },
    "packages/b": { name: "b" },
    "packages/excluded": { name: "excluded" },
    "tools/c": { name: "c" },
    "packages/a/node_modules/hidden": { name: "hidden" },
  };
  const cwd = await fixture(
    t,
    Object.fromEntries(
      Object.entries(packages).map(([directory, pkg]) => [
        `${directory}/package.json`,
        JSON.stringify(pkg),
      ]),
    ),
  );
  const pkg = { workspaces: ["{packages,tools}/*", "!packages/excluded"] };
  const actual = await mapWorkspaces({ cwd, pkg });
  const expected = ["a", "b", "c"].map((name) => [
    name,
    path.join(cwd, name === "c" ? "tools/c" : `packages/${name}`),
  ]);
  assert.deepEqual([...actual], expected);
  assert.deepEqual(
    [
      ...mapWorkspaces.virtual({
        cwd,
        lockfile: { packages: { "": pkg, ...packages } },
      }),
    ],
    expected,
  );
  const reincluded = await mapWorkspaces({
    cwd,
    pkg: { workspaces: ["packages/*", "!packages/b", "packages/b"] },
  });
  assert.deepEqual([...reincluded.keys()], ["a", "b", "excluded"]);
  const ordered = {
    workspaces: ["tools/*", "packages/**", "!packages/excluded"],
  };
  assert.deepEqual(
    [...(await mapWorkspaces({ cwd, pkg: ordered })).keys()],
    ["c", "a", "b"],
  );
  assert.deepEqual(
    [
      ...mapWorkspaces
        .virtual({ cwd, lockfile: { packages: { "": ordered, ...packages } } })
        .keys(),
    ],
    ["c", "a", "b"],
  );
});

test("package-json preparation preserves glob-based metadata discovery", async (t) => {
  const cwd = await fixture(t, {
    "package.json": JSON.stringify({
      name: "fixture",
      version: "1.0.0",
      directories: { man: "man", bin: "bin" },
    }),
    "ReadMe.MD": "# Fixture\n",
    "README.md/ignored": "directory, not a readme\n",
    "binding.gyp": "{}\n",
    "man/fixture.1": "manual\n",
    "bin/fixture": "#!/bin/sh\n",
  });
  const pkg = await PackageJson.prepare(cwd, {
    steps: ["gypfile", "readme", "mans", "binDir"],
  });
  assert.equal(pkg.content.scripts.install, "node-gyp rebuild");
  assert.equal(pkg.content.readmeFilename, "ReadMe.MD");
  assert.equal(pkg.content.readme, "# Fixture\n");
  assert.deepEqual(pkg.content.man, ["man/fixture.1"]);
  assert.deepEqual(pkg.content.bin, { fixture: "bin/fixture" });
});

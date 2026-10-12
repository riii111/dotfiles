import { execFileSync } from "node:child_process";
import { engine } from "unified-engine";
import { remark } from "remark";
import remarkConfig from "./remark.config.mjs";
import { readFile, writeFile, lstat } from "node:fs/promises";
import path from "node:path";
import { makeLinter, formatText, repoRoot, toolDir } from "./linter.mjs";

const usage =
  "Usage: npm --prefix scripts/ai-docs run <lint|fmt|links> -- [--json|--strict|--check] [file.md ...]";

async function main() {
  const [command, ...args] = process.argv.slice(2);
  if (!command || args.includes("--help")) {
    console.log(usage);
    return;
  }
  if (!["lint", "fmt", "links"].includes(command)) throw new Error(usage);
  const allowed =
    command === "lint"
      ? ["--json", "--strict"]
      : command === "fmt"
        ? ["--check"]
        : [];
  const flags = args.filter((arg) => arg.startsWith("--"));
  if (flags.some((flag) => !allowed.includes(flag))) throw new Error(usage);
  let files = args.filter((arg) => !arg.startsWith("--"));
  if (!files.length) {
    if (command === "fmt")
      throw new Error("fmtには変更対象のMarkdownファイルを指定してください。");
    files = execFileSync(
      "git",
      ["ls-files", "-z", "--", "dot_codex/skills", "dot_claude/skills"],
      { cwd: repoRoot, encoding: "utf8" },
    )
      .split("\0")
      .filter((file) => file.endsWith(".md"));
  }
  files = [
    ...new Set(files.map((file) => path.resolve(repoRoot, file))),
  ].sort();
  if (!files.length) throw new Error("対象のMarkdownファイルがありません。");
  for (const file of files) {
    if (!file.endsWith(".md") || !(await lstat(file)).isFile())
      throw new Error(`通常のMarkdownファイルを指定してください: ${file}`);
  }
  if (command === "links") {
    process.exitCode = await new Promise((resolve, reject) => {
      engine(
        {
          processor: remark,
          plugins: remarkConfig.plugins,
          cwd: repoRoot,
          files,
          extensions: ["md"],
          detectConfig: false,
          detectIgnore: false,
          output: false,
          out: false,
          frail: true,
          quiet: true,
        },
        (error, status) => (error ? reject(error) : resolve(status)),
      );
    });
    console.log(`${files.length} files, links checked`);
    return;
  }
  const linter = await makeLinter();
  if (command === "fmt") {
    let changed = 0;
    for (const file of files) {
      const source = await readFile(file, "utf8");
      const output = await formatText(linter, source, file);
      if (output !== source) {
        changed++;
        console.log(path.relative(repoRoot, file));
        if (!flags.includes("--check")) await writeFile(file, output);
      }
    }
    console.log(
      `${files.length} files, ${changed} ${flags.includes("--check") ? "would change" : "changed"}`,
    );
    if (flags.includes("--check") && changed) process.exitCode = 1;
    return;
  }
  const results = [];
  for (const file of files) {
    const source = await readFile(file, "utf8");
    const result = await linter.lintText(source, file);
    // Older third-party rules can report a column relative to the whole node.
    for (const message of result.messages) {
      const locate = (index) => {
        const prefix = source.slice(0, index);
        return {
          line: prefix.split("\n").length,
          column: prefix.length - prefix.lastIndexOf("\n"),
        };
      };
      message.loc = {
        start: locate(message.range[0]),
        end: locate(message.range[1]),
      };
      message.line = message.loc.start.line;
      message.column = message.loc.start.column;
    }
    results.push(result);
  }
  const messages = results.flatMap((result) => result.messages);
  if (flags.includes("--json")) console.log(JSON.stringify(results, null, 2));
  else {
    for (const result of results) {
      for (const message of result.messages) {
        console.log(
          `${path.relative(repoRoot, result.filePath)}:${message.line}:${message.column} ${message.ruleId}: ${message.message}`,
        );
      }
    }
    console.log(`${files.length} files, ${messages.length} warnings`);
  }
  if (
    messages.some((message) => message.severity === 2) ||
    (flags.includes("--strict") && messages.length)
  )
    process.exitCode = 1;
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});

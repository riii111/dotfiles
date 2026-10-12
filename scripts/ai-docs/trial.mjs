import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { makeLinter, formatText, repoRoot } from "./linter.mjs";

const files = execFileSync(
  "git",
  ["ls-files", "-z", "--", "dot_codex/skills", "dot_claude/skills"],
  { cwd: repoRoot, encoding: "utf8" },
)
  .split("\0")
  .filter((file) => file.endsWith(".md"))
  .sort();
const linter = makeLinter();
const counts = { before: {}, after: {} };
const sourceLines = [];
let changed = 0;
let idempotent = 0;
const failures = [];
for (const file of files) {
  const filePath = path.join(repoRoot, file);
  const source = await readFile(filePath, "utf8");
  const before = await linter.lintText(source, filePath);
  for (const message of before.messages) {
    counts.before[message.ruleId] = (counts.before[message.ruleId] ?? 0) + 1;
    if (message.ruleId === "source-line")
      sourceLines.push(`${file}:${message.line}`);
  }
  try {
    const formatted = await formatText(linter, source, filePath);
    if (formatted !== source) changed++;
    if (formatted === (await formatText(linter, formatted, filePath)))
      idempotent++;
    else failures.push({ file, error: "再整形で差分が発生" });
    const after = await linter.lintText(formatted, filePath);
    for (const message of after.messages)
      counts.after[message.ruleId] = (counts.after[message.ruleId] ?? 0) + 1;
  } catch (error) {
    failures.push({ file, error: error.message });
  }
}
const sampleSize = Math.min(40, sourceLines.length);
const reviewedSourceLines = Array.from(
  { length: sampleSize },
  (_, i) =>
    sourceLines[
      Math.round((i * (sourceLines.length - 1)) / Math.max(1, sampleSize - 1))
    ],
);
console.log(
  JSON.stringify(
    {
      files: files.length,
      counts,
      changed,
      idempotent,
      failures,
      sourceLineSample: reviewedSourceLines,
    },
    null,
    2,
  ),
);
if (failures.length) process.exitCode = 1;

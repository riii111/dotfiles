/// <reference path="./vendor-rules.d.ts" />

import redundantExpression from "textlint-rule-ja-no-redundant-expression";
import sentenceLength from "textlint-rule-sentence-length";
import longParentheses from "./rules/long-parentheses.mjs";
import proseLines from "./rules/prose-lines.mjs";
import sourceLine from "./rules/source-line.mjs";

export default [
  ["source-line", sourceLine],
  ["long-parentheses", longParentheses, { maxLength: 40 }],
  ["prose-lines", proseLines, { skillMax: 80, max: 100 }],
  [
    "sentence-length",
    sentenceLength,
    { max: 100, skipPatterns: ["/^[\\x00-\\x7F]+$/u"] },
  ],
  ["ja-no-redundant-expression", redundantExpression],
].map(([ruleId, rule, options]) => ({
  ruleId,
  rule: rule.default ?? rule,
  options: { ...options, severity: "warning" },
}));

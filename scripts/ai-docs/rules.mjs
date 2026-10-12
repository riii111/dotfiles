import sourceLine from "./rules/source-line.mjs";
import labelList from "./rules/label-list.mjs";
import longParentheses from "./rules/long-parentheses.mjs";
import sentenceLength from "textlint-rule-sentence-length";
import redundantExpression from "textlint-rule-ja-no-redundant-expression";

export default [
  ["source-line", sourceLine, { maxSupplementLength: 20 }],
  ["label-list", labelList],
  ["long-parentheses", longParentheses, { maxLength: 40 }],
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

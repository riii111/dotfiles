declare module "textlint-rule-ja-no-redundant-expression" {
  const rule: {
    default: import("@textlint/types").TextlintFixableRuleModule;
  };
  export default rule;
}

declare module "textlint-rule-sentence-length" {
  const rule: {
    default: import("@textlint/types").TextlintRuleReporter<{
      max?: number;
      skipPatterns?: string[];
    }>;
  };
  export default rule;
}

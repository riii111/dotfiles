declare module "textlint-rule-ja-no-redundant-expression" {
  const rule: {
    default: import("@textlint/types").TextlintFixableRuleModule;
  };
  export default rule;
}

declare module "textlint-rule-max-ten" {
  const rule: import("@textlint/types").TextlintRuleReporter<{
    max?: number;
  }>;
  export default rule;
}

declare module "textlint-rule-no-double-negative-ja" {
  const rule: {
    default: import("@textlint/types").TextlintRuleReporter;
  };
  export default rule;
}

declare module "textlint-rule-no-doubled-conjunctive-particle-ga" {
  const rule: {
    default: import("@textlint/types").TextlintRuleReporter;
  };
  export default rule;
}

declare module "textlint-rule-no-doubled-joshi" {
  const rule: {
    default: import("@textlint/types").TextlintRuleReporter<{
      allow?: string[];
    }>;
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

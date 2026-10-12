import frontmatter from "remark-frontmatter";
import gfm from "remark-gfm";
import validateLinks from "remark-validate-links";
import { fileURLToPath } from "node:url";

export default {
  plugins: [
    frontmatter,
    gfm,
    [
      validateLinks,
      {
        root: fileURLToPath(new URL("../../", import.meta.url)),
        repository: false,
        // These destinations are placeholders in the repository's review templates.
        skipPathPatterns: [
          /\/\{(?:skill_path|cycle_skill_path|reply_path|worker_skill_path)\}(?:#.*)?$/u,
          /\/dot_codex\/skills\/adr-review\/templates\/(?:直接リンク|検証済みの行URL|URL)$/u,
        ],
      },
    ],
  ],
};

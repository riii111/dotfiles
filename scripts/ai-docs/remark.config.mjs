import { fileURLToPath } from "node:url";
import frontmatter from "remark-frontmatter";
import gfm from "remark-gfm";
import validateLinks from "remark-validate-links";

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
          /\/reply-\{worker_ai\}\.md$/u,
          /\/dot_codex\/skills\/adr-review\/templates\/(?:直接リンク|検証済みの行URL|URL)$/u,
        ],
      },
    ],
  ],
};

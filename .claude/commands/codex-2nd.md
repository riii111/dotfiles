---
description: Get a repo-aware 2nd opinion from Codex (English), then discuss in Japanese.
argument-hint: "One extra instruction/constraint to pass through (free-form)."
allowed-tools: Bash(codex exec:*)
---

## Task (Claude Code)
We are mid-discussion. Use this command to obtain a **2nd opinion** from Codex to complement our current findings.

Requirements:
- Communicate with Codex **in English**.
- Assume the repo contains **AGENTS.md** with baseline project context; Codex may read it but **must not restate it**.
- Prefer no back-and-forth: Codex should gather necessary info by inspecting the repo itself.
  If uncertain, Codex should state assumptions explicitly and proceed. Questions are a last resort.

### 1) Write a compact English brief (tight)
Include only:
- Goal / decision (1–2 lines)
- What we already know / tried / observed (bullets)
- Constraints / non-goals (bullets)
- Extra instruction from user (verbatim): "$ARGUMENTS"

### 2) Run Codex via Bash tool (read-only, no approvals; prompt via stdin)
Using the Bash tool, run **exactly** the command below after you paste the brief:

```bash
RUST_LOG=RUST_LOG=off codex exec --sandbox read-only 2>/dev/null - <<'CODEX_PROMPT'
You are Codex, acting as a senior engineer providing a second opinion.

Operating rules:
- English only.
- Independently inspect the repository as needed (read-only). You may run safe read-only commands (e.g., git status/log/diff, rg, ls, cat) and open relevant files.
- Read AGENTS.md for baseline context, but DO NOT restate it.
- No web browsing; stay within the repo and local signals.
- Prefer not to ask questions. If uncertain, list assumptions and proceed.

What I want from you (best-practice + pragmatic + thorough repo inspection):
1) Top blind spots / risks (prioritized, concise)
2) Recommended approach (best practices + pragmatic compromise), with trade-offs
3) Concrete next steps (ordered, max 7, each step actionable in this repo)
4) Assumptions made (explicit)

=== CONTEXT FROM CLAUDE CODE (English brief) ===
<PASTE_BRIEF_HERE>
CODEX_PROMPT

3) Share back to the user (Japanese, conversational)

Summarize Codex’s result in Japanese and continue discussion naturally:
	•	重要な指摘（必要なら3つ以上でもOK）
	•	次にやること（目安5つ前後、順番つき）
	•	追加で当たるべき調査ポイント（ファイル名/grep観点/コマンド例など）
	•	必要なら、確認質問や選択肢も提示してOK


# Review Format Template

This file defines the review file format for the local AI review workflow.

## File Structure

```
reviews/{branch}/codex.md    ← codex reviewer
reviews/{branch}/cc-rev.md   ← CC reviewer
```

## Format Rules

- One file per reviewer per branch
- Each comment thread is a `## [ID] file:line` section
- Wrap each thread body in `~~~` fences for visual clarity
- Inside a thread, use `### {reviewer-name}` to mark each reply
- Code snippets inside threads use ` ``` ` (no conflict with outer `~~~`)
- Replies are ordered top-to-bottom chronologically
- Comment IDs are sequential: `[C1]`, `[C2]`, ...

## Example

```markdown
# Review: feature/add-auth

<!-- reviewer: codex -->

## [C1] src/auth/login.rs:42

~~~
### codex
`unwrap()` はパニックの可能性がある。理由：

- 外部入力に依存している
- エラー時のリカバリパスがない

```rust
// 現状
let config = load_config().unwrap();

// 提案
let config = load_config().map_err(|e| AppError::Config(e))?;
```

### impl
起動時の初期化で、失敗=停止が正しい。

根拠：
- この関数は `main()` の冒頭でのみ呼ばれる
- 設定ファイルが壊れた状態で続行するほうが危険

`expect()` に変更して意図を明示するのはどうか。

### codex
`expect()` なら妥当。ただしメッセージを具体的にしてほしい。

### impl
了解、修正する。
~~~

## [C2] src/auth/session.rs:15

~~~
### codex
セッションTTLがハードコードされている。

問題点：
- 環境ごとにTTLを変えたいケースがある
- テスト時に短いTTLを設定できない

### impl
MVP段階で意図的なハードコード。

- 次イシュー (#42) で設定化を対応予定
- 現時点では固定値で十分

### codex
了解。TODOコメントがあれば十分。
~~~
```

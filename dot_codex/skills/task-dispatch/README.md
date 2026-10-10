# Task Dispatchのファイル構成

[SKILL.md](SKILL.md)が実行の入口。1日の流れ・実行別の手順・共通制約を持ち、各手順から必要な詳細を`references/`で参照する。

## スキルの文書

```text
task-dispatch/
├── README.md           # ファイルの配置と関係
├── SKILL.md            # 実行の入口と共通ルール
├── agents/openai.yaml  # 表示名・呼び出し設定
└── references/
    ├── config.md       # 設定項目・定期実行の登録・試運転
    ├── schedule.md     # 日程とスレッドの管理
    ├── plan.md         # 候補の発見・着手判断・予定作成
    ├── launch.md       # 承認と新規起動
    ├── continue.md     # 既存workerへの続行
    ├── item.md         # 台帳の形式と状態遷移
    └── digest.md       # 予定・報告・返事の書式
```

## 文書の関係

- [config.md](references/config.md)の設定を使い、[schedule.md](references/schedule.md)が予定作成の時刻を決める。
- [plan.md](references/plan.md)で選んだ仕事を、承認後に[launch.md](references/launch.md)で起動する。既存workerへの追加指示は[continue.md](references/continue.md)が扱う。
- 各処理の状態と履歴は[item.md](references/item.md)の形式で記録し、利用者への出力は[digest.md](references/digest.md)の書式でまとめる。

## 作業データ

スキルの文書とは別に、`~/agent-desk/`に設定と実行結果を置く。

```text
~/agent-desk/
├── config.yaml                 # 発見元・リポジトリ・上限・owner・Calendarの設定
├── items/<file>.yaml           # 1仕事1ファイルの台帳
├── requests/<file>.json        # itemと同じファイル名の起動依頼
├── days/<日付>.yaml            # 退勤予定・Scheduled Task・予定スレッドの情報
├── decisions/<itemのファイル名>.md  # ownerが答えた大きな判断のメモ
├── runs/
│   ├── <日付>-plan.md           # 今夜の予定
│   └── <日付>-report.md         # 朝の報告
└── .lock/started_at            # 実行の重複を防ぐlockと開始時刻
```

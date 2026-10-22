# PRの積み方

PRを積むかどうかの基準はこの文書だけに置く。
決めるのは`$task-session-launch`を呼び出す側で、起動の前に決める。
起動後は積み直さない。
Approveは最後のpush以降のものだけがマージ条件に数えられ、Open後のbase付け替えやrebaseのpushで失われるため。

## 基準

次のどちらかに当てはまる場合だけ、前のPRの上に積む。

- Blocked byがある、または後のPRが前のPRのコードを使う。
- 変更するファイルが重なっていて、コンフリクトが見込まれる。

それ以外はmainから独立して出す。
積むと、1本が止まったときに上のPRも待たされるため。
迷ったら積まない。

## 段数と積み先

- 積み先は、openでmainから2段目までのPRとする。
  積んだPRを含めて3段までになる。
- 積み先は、そのPRのbranchをbaseにするopenのPRがないPR（stackの最上段）に限る。
  既存stackの途中や、すでに別のPRを積んだPRには積まない。
  同じ予定や同じ回の開始対象で、同じPRを複数の積み先にしない。
  該当する積み先がなければ、積まずに待つか、mainから独立して出す。
- 段数はPRのbaseをmainまでたどって数える。
- 積み先のPRがまだない場合は、そのPRができるまで積む側を起動しない。

## 起動依頼への反映

積む場合は、起動依頼JSONに次を記録する。

- startingBranch: 積み先のPRのhead branch。
- documentRefs: 積み先のPRのURLを加える。
  workerが積み先を確認できるようにするため。

積まない場合は、startingBranchを省略する。

## workerの作業

workerは[task-worker](../../task-worker/SKILL.md#積んだpr)に従い、PRのbaseを積み先のbranchにして`gh stack link`でstackへ載せる。

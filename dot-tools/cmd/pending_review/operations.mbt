///|
priv struct Target {
  owner : String
  name : String
  number : Int32
}

///|
priv enum Side {
  Left
  Right
}

///|
fn Side::name(self : Side) -> String {
  match self {
    Left => "LEFT"
    Right => "RIGHT"
  }
}

///|
priv struct Draft {
  path : String
  line : Int32
  side : Side
  body : String
}

///|
// Submitting, replying and resolving have no variant, so no input can make this command publish anything.
priv enum Operation {
  Viewer
  Snapshot(Target)
  PullFiles(Target, Int32)
  StartReview(String, String)
  AddThread(String, Draft, String)
}

///|
let snapshot_query : String =
  #|query($owner: String!, $name: String!, $number: Int!) {
  #|  repository(owner: $owner, name: $name) {
  #|    pullRequest(number: $number) {
  #|      id
  #|      state
  #|      headRefOid
  #|      url
  #|      reviews(states: PENDING, first: 10) {
  #|        pageInfo { hasNextPage }
  #|        nodes {
  #|          id
  #|          state
  #|          url
  #|          author { login }
  #|          commit { oid }
  #|          comments(first: 100) {
  #|            pageInfo { hasNextPage }
  #|            nodes { id path line originalLine body }
  #|          }
  #|        }
  #|      }
  #|    }
  #|  }
  #|}

///|
// No `event` is passed, which leaves the review pending.
let start_review_query : String =
  #|mutation($pull: ID!, $commit: GitObjectID!) {
  #|  addPullRequestReview(input: { pullRequestId: $pull, commitOID: $commit }) {
  #|    pullRequestReview { id state }
  #|  }
  #|}

///|
let add_thread_query : String =
  #|mutation($review: ID!, $path: String!, $line: Int!, $side: DiffSide!, $body: String!) {
  #|  addPullRequestReviewThread(input: {
  #|    pullRequestReviewId: $review, path: $path, line: $line, side: $side, body: $body, subjectType: LINE
  #|  }) {
  #|    thread { comments(first: 1) { nodes { id state } } }
  #|  }
  #|}

///|
fn graphql(
  query : String,
  strings : Array[(String, String)],
  numbers : Array[(String, Int32)],
) -> Array[String] {
  let args = ["api", "graphql", "-f", "query=\{query}"]
  for entry in strings {
    args.push("-f")
    args.push("\{entry.0}=\{entry.1}")
  }
  // `-F` converts a numeric value to an integer; strings always go through `-f` so a body such as `true` stays text.
  for entry in numbers {
    args.push("-F")
    args.push("\{entry.0}=\{entry.1}")
  }
  args
}

///|
fn gh_args(operation : Operation) -> Array[String] {
  match operation {
    Viewer => graphql("query { viewer { login } }", [], [])
    Snapshot(target) =>
      graphql(
        snapshot_query,
        [("owner", target.owner), ("name", target.name)],
        [("number", target.number)],
      )
    PullFiles(target, page) =>
      [
        "api",
        "repos/\{target.owner}/\{target.name}/pulls/\{target.number}/files?per_page=100&page=\{page}",
      ]
    StartReview(pull_id, commit) =>
      graphql(start_review_query, [("pull", pull_id), ("commit", commit)], [])
    AddThread(review_id, draft, body) =>
      graphql(
        add_thread_query,
        [
          ("review", review_id),
          ("path", draft.path),
          ("side", draft.side.name()),
          ("body", body),
        ],
        [("line", draft.line)],
      )
  }
}

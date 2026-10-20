package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const headSHA = "0123456789abcdef0123456789abcdef01234567"

type call struct {
	name string
	args []string
}

// fakeRunner answers each command by the first handler whose key prefixes "name arg1 arg2 ...".
type fakeRunner struct {
	handlers []handler
	calls    []call
}

type handler struct {
	prefix string
	answer func(args []string) ([]byte, error)
}

func (f *fakeRunner) on(prefix string, answer func(args []string) ([]byte, error)) {
	f.handlers = append(f.handlers, handler{prefix, answer})
}

func (f *fakeRunner) reply(prefix, out string) {
	f.on(prefix, func([]string) ([]byte, error) { return []byte(out), nil })
}

func (f *fakeRunner) Run(_ context.Context, name string, args ...string) ([]byte, error) {
	f.calls = append(f.calls, call{name, args})
	line := strings.Join(append([]string{name}, args...), " ")
	for _, h := range f.handlers {
		if strings.HasPrefix(line, h.prefix) {
			return h.answer(args)
		}
	}
	return nil, fmt.Errorf("unexpected command: %s", line)
}

func (f *fakeRunner) ran(prefix string) bool {
	for _, c := range f.calls {
		if strings.HasPrefix(strings.Join(append([]string{c.name}, c.args...), " "), prefix) {
			return true
		}
	}
	return false
}

func testEnv(t *testing.T, skills ...string) Env {
	t.Helper()
	home := t.TempDir()
	codex := filepath.Join(home, ".codex")
	for _, s := range skills {
		dir := filepath.Join(codex, "skills", s)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, "SKILL.md"), []byte("# "+s), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return Env{Home: home, CodexHome: codex}
}

func choiceJSON(id, label, skill string) string {
	return fmt.Sprintf(`{"id":%q,"label":%q,"skill":%q,"prompt":"[${{.Skill}}]({{.SkillPath}}) {{.PR.URL}} {{.PR.HeadSHA}} {{.Worktree}}"}`, id, label, skill)
}

func configJSON(choices ...string) string {
	return `{"repositories":{"acme/app":"~/src/app"},"choices":[` + strings.Join(choices, ",") + `]}`
}

func mustConfig(t *testing.T, env Env, data string) *Config {
	t.Helper()
	cfg, err := parseConfig([]byte(data), env)
	if err != nil {
		t.Fatal(err)
	}
	return cfg
}

func TestConfigResolvesPathsAndDefaults(t *testing.T) {
	env := testEnv(t, "adr-review")
	cfg := mustConfig(t, env, configJSON(choiceJSON("adr", "ADRレビュー", "adr-review")))
	if got, want := cfg.Repositories["acme/app"], filepath.Join(env.Home, "src", "app"); got != want {
		t.Errorf("repository path = %q, want %q", got, want)
	}
	if got, want := cfg.WorktreeRoot, filepath.Join(env.Home, ".local", "share", "review-notifier", "worktrees"); got != want {
		t.Errorf("worktreeRoot = %q, want %q", got, want)
	}
	if cfg.NotificationTimeoutSeconds != defaultTimeoutSeconds {
		t.Errorf("timeout = %d", cfg.NotificationTimeoutSeconds)
	}
	if got, want := cfg.Choices[0].skillPath, filepath.Join(env.CodexHome, "skills", "adr-review", "SKILL.md"); got != want {
		t.Errorf("skillPath = %q, want %q", got, want)
	}
}

func TestConfigRejectsInvalidEntries(t *testing.T) {
	env := testEnv(t, "adr-review", "code-review")
	adr := choiceJSON("adr", "ADRレビュー", "adr-review")
	cases := map[string]string{
		"no choices":         configJSON(),
		"unsupported key":    `{"choices":[{"id":"adr","label":"ADR","skill":"adr-review","prompt":"x","model":"gpt"}]}`,
		"duplicate id":       configJSON(adr, choiceJSON("adr", "コードレビュー", "code-review")),
		"duplicate label":    configJSON(adr, choiceJSON("code", "ADRレビュー", "code-review")),
		"comma in label":     configJSON(choiceJSON("adr", "ADR,レビュー", "adr-review")),
		"missing skill":      configJSON(choiceJSON("adr", "ADR", "no-such-skill")),
		"skill path escape":  configJSON(choiceJSON("adr", "ADR", "../adr-review")),
		"unknown field":      configJSON(`{"id":"adr","label":"ADR","skill":"adr-review","prompt":"{{.PR.Nope}}"}`),
		"relative repo path": `{"repositories":{"acme/app":"src/app"},"choices":[` + adr + `]}`,
		"bad repo name":      `{"repositories":{"acme":"/src/app"},"choices":[` + adr + `]}`,
		"relative command":   `{"commands":{"gh":"gh"},"choices":[` + adr + `]}`,
	}
	for name, data := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := parseConfig([]byte(data), env); err == nil {
				t.Fatal("expected an error")
			}
		})
	}
}

func TestChoicesFollowConfigOrderInNotification(t *testing.T) {
	env := testEnv(t, "adr-review", "code-review", "ai-code-review")
	cfg := mustConfig(t, env, configJSON(
		choiceJSON("code", "コードレビュー", "code-review"),
		choiceJSON("ai", "AIレビュー", "ai-code-review"),
		choiceJSON("adr", "ADRレビュー", "adr-review"),
	))
	args := alerterArgs(Notice{Key: "k", PR: PullRequest{Repo: "acme/app", Number: 7, Title: "A\nB"}, Requester: "tanaka"}, cfg.Choices, 60)
	got := argValue(t, args, "--actions")
	if got != "コードレビュー,AIレビュー,ADRレビュー" {
		t.Errorf("--actions = %q", got)
	}
	if got := argValue(t, args, "--subtitle"); got != "A B" {
		t.Errorf("--subtitle = %q", got)
	}
	if got := argValue(t, args, "--message"); got != "依頼者: @tanaka\nacme/app #7" {
		t.Errorf("--message = %q", got)
	}
	if got := argValue(t, args, "--close-label"); got != "見送る" {
		t.Errorf("--close-label = %q", got)
	}
}

func TestNotificationMarksUnknownRequester(t *testing.T) {
	ch := []Choice{{Label: "ADR"}}
	args := alerterArgs(Notice{PR: PullRequest{Repo: "acme/app", Number: 7}}, ch, 60)
	if got := argValue(t, args, "--message"); !strings.HasPrefix(got, "依頼者不明\n") {
		t.Errorf("--message = %q", got)
	}
	for _, a := range args {
		if a == "--dropdown-label" {
			t.Error("a single action needs no dropdown label")
		}
	}
}

func argValue(t *testing.T, args []string, flag string) string {
	t.Helper()
	for i := 0; i+1 < len(args); i++ {
		if args[i] == flag {
			return args[i+1]
		}
	}
	t.Fatalf("%s missing in %q", flag, args)
	return ""
}

func TestParseSelection(t *testing.T) {
	choices := []Choice{{ID: "adr", Label: "ADRレビュー"}, {ID: "code", Label: "コードレビュー"}}
	cases := []struct {
		name    string
		out     string
		outcome Outcome
		id      string
		fails   bool
	}{
		{"dropdown", `{"activationType":"actionClicked","activationValue":"コードレビュー","activationValueIndex":"1"}`, Chosen, "code", false},
		{"single action", `{"activationType":"actionClicked","activationValue":"ADRレビュー"}`, Chosen, "adr", false},
		{"decline", `{"activationType":"closed","activationValue":"見送る"}`, Declined, "", false},
		{"timeout", `{"activationType":"timeout"}`, TimedOut, "", false},
		{"body click", `{"activationType":"contentsClicked"}`, Dismissed, "", false},
		{"index and value disagree", `{"activationType":"actionClicked","activationValue":"ADRレビュー","activationValueIndex":"1"}`, "", "", true},
		{"index out of range", `{"activationType":"actionClicked","activationValue":"x","activationValueIndex":"5"}`, "", "", true},
		{"unknown label", `{"activationType":"actionClicked","activationValue":"x"}`, "", "", true},
		{"not json", `@CLOSED`, "", "", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			sel, err := parseSelection([]byte(c.out), choices)
			if c.fails {
				if err == nil {
					t.Fatalf("expected an error, got %+v", sel)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if sel.Outcome != c.outcome {
				t.Errorf("outcome = %s", sel.Outcome)
			}
			if c.id != "" && (sel.Choice == nil || sel.Choice.ID != c.id) {
				t.Errorf("choice = %+v", sel.Choice)
			}
			if c.id == "" && sel.Choice != nil {
				t.Errorf("no choice expected, got %+v", sel.Choice)
			}
		})
	}
}

func TestDeepLinkEncodesPromptAndPath(t *testing.T) {
	prompt := "[$code-review](/x/SKILL.md)\nPR: https://github.com/a/b/pull/1?x=1&y=2#frag 100% +ok"
	path := "/Users/me/review worktrees/a&b"
	link := deepLink(prompt, path)
	if strings.ContainsAny(link[len("codex://new?"):], " \n#+") {
		t.Errorf("unescaped characters in %q", link)
	}
	u, err := url.Parse(link)
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	if q.Get("prompt") != prompt || q.Get("path") != path {
		t.Errorf("round trip: prompt=%q path=%q", q.Get("prompt"), q.Get("path"))
	}
}

func TestParsePRRef(t *testing.T) {
	for ref, want := range map[string]string{
		"acme/app#12":                               "acme/app#12",
		"https://github.com/acme/app/pull/12":       "acme/app#12",
		"https://github.com/acme/app/pull/12/files": "acme/app#12",
	} {
		repo, n, err := parsePRRef(ref)
		if err != nil || fmt.Sprintf("%s#%d", repo, n) != want {
			t.Errorf("%s: %s#%d %v", ref, repo, n, err)
		}
	}
	for _, ref := range []string{"acme/app", "acme/app#0", "acme/app#x", "a b/c#1", "https://github.com/acme/app/issues/1", "acme/app;rm#1"} {
		if _, _, err := parsePRRef(ref); err == nil {
			t.Errorf("%s: expected an error", ref)
		}
	}
}

func prJSON(repo string, number int) string {
	return fmt.Sprintf(`{"number":%d,"title":"検索基盤にOpenTelemetryを導入する","html_url":"https://github.com/%s/pull/%d","head":{"sha":%q},"base":{"ref":"main","repo":{"full_name":%q}}}`, number, repo, number, headSHA, repo)
}

func TestFetchPR(t *testing.T) {
	r := &fakeRunner{}
	r.reply("gh api repos/acme/app/pulls/12", prJSON("acme/app", 12))
	pr, err := fetchPR(context.Background(), r, "gh", "acme/app", 12)
	if err != nil {
		t.Fatal(err)
	}
	if pr.HeadSHA != headSHA || pr.BaseRef != "main" || pr.URL != "https://github.com/acme/app/pull/12" {
		t.Errorf("pr = %+v", pr)
	}
	if _, err := parsePR([]byte(prJSON("other/app", 12)), "acme/app", 12); err == nil {
		t.Error("a different repository must be rejected")
	}
	bad := strings.Replace(prJSON("acme/app", 12), headSHA, "main", 1)
	if _, err := parsePR([]byte(bad), "acme/app", 12); err == nil {
		t.Error("a head that is not a SHA must be rejected")
	}
}

func TestRemoteRepo(t *testing.T) {
	for remote, want := range map[string]string{
		"git@github.com:acme/app.git\n":     "acme/app",
		"https://github.com/acme/app":       "acme/app",
		"https://github.com/acme/app.git":   "acme/app",
		"ssh://git@github.com/acme/app.git": "acme/app",
	} {
		if got, ok := remoteRepo(remote); !ok || got != want {
			t.Errorf("%q: %q %v", remote, got, ok)
		}
	}
	if _, ok := remoteRepo("https://gitlab.com/acme/app.git"); ok {
		t.Error("non-GitHub remote must not match")
	}
}

func worktreeFixture(t *testing.T) (*Config, PullRequest) {
	env := testEnv(t, "code-review")
	cfg := mustConfig(t, env, configJSON(choiceJSON("code", "コードレビュー", "code-review")))
	pr := PullRequest{Repo: "acme/app", Number: 12, HeadSHA: headSHA}
	return cfg, pr
}

func TestPrepareWorktreeFetchesAndCreatesDetached(t *testing.T) {
	cfg, pr := worktreeFixture(t)
	checkout := cfg.Repositories["acme/app"]
	want := worktreePath(cfg.WorktreeRoot, pr)
	r := &fakeRunner{}
	r.reply("git -C "+checkout+" remote get-url origin", "git@github.com:acme/app.git\n")
	fetched := false
	r.on("git -C "+checkout+" cat-file -e", func([]string) ([]byte, error) {
		if fetched {
			return nil, nil
		}
		return nil, errors.New("missing")
	})
	r.on("git -C "+checkout+" fetch", func([]string) ([]byte, error) { fetched = true; return nil, nil })
	r.reply("git -C "+checkout+" worktree add --detach "+want+" "+headSHA, "")

	got, err := prepareWorktree(context.Background(), r, "git", cfg, pr)
	if err != nil {
		t.Fatal(err)
	}
	if got != want || !strings.HasSuffix(want, "acme/app/pr-12-0123456789ab") {
		t.Errorf("path = %q", got)
	}
	if !r.ran("git -C " + checkout + " fetch --no-tags --no-write-fetch-head origin refs/pull/12/head") {
		t.Error("expected a fetch of the pull ref")
	}
	for _, c := range r.calls {
		joined := strings.Join(c.args, " ")
		if strings.Contains(joined, " checkout") || strings.Contains(joined, " switch") || strings.Contains(joined, " reset") {
			t.Errorf("the checkout must not change: %s", joined)
		}
	}
}

func TestPrepareWorktreeRejectsOtherOrigin(t *testing.T) {
	cfg, pr := worktreeFixture(t)
	r := &fakeRunner{}
	r.reply("git -C "+cfg.Repositories["acme/app"]+" remote get-url origin", "git@github.com:acme/other.git\n")
	if _, err := prepareWorktree(context.Background(), r, "git", cfg, pr); err == nil {
		t.Fatal("expected an error")
	}
	if r.ran("git -C " + cfg.Repositories["acme/app"] + " worktree") {
		t.Error("no worktree may be created")
	}
}

func TestPrepareWorktreeRequiresConfiguredCheckout(t *testing.T) {
	cfg, pr := worktreeFixture(t)
	pr.Repo = "acme/unknown"
	r := &fakeRunner{}
	if _, err := prepareWorktree(context.Background(), r, "git", cfg, pr); err == nil || len(r.calls) != 0 {
		t.Fatalf("err = %v, calls = %v", err, r.calls)
	}
}

func TestPrepareWorktreeReusesSameHeadOnly(t *testing.T) {
	cfg, pr := worktreeFixture(t)
	path := worktreePath(cfg.WorktreeRoot, pr)
	if err := os.MkdirAll(path, 0o700); err != nil {
		t.Fatal(err)
	}
	r := &fakeRunner{}
	r.reply("git -C "+cfg.Repositories["acme/app"]+" remote get-url origin", "https://github.com/acme/app.git\n")
	head := headSHA
	r.on("git -C "+path+" rev-parse HEAD", func([]string) ([]byte, error) { return []byte(head + "\n"), nil })
	got, err := prepareWorktree(context.Background(), r, "git", cfg, pr)
	if err != nil || got != path {
		t.Fatalf("got %q, %v", got, err)
	}
	head = strings.Repeat("f", 40)
	if _, err := prepareWorktree(context.Background(), r, "git", cfg, pr); err == nil {
		t.Fatal("a worktree at another commit must not be reused")
	}
}

func TestSmokeDeclineStartsNothing(t *testing.T) {
	env := testEnv(t, "code-review")
	configPath := writeConfig(t, env, configJSON(choiceJSON("code", "コードレビュー", "code-review")))
	r := &fakeRunner{}
	r.reply("/bin/gh api", prJSON("acme/app", 12))
	r.reply("/bin/alerter", `{"activationType":"closed","activationValue":"見送る"}`)
	var out bytes.Buffer
	err := runSmoke(context.Background(), []string{"--config", configPath, "--pr", "acme/app#12"}, env, r, &out)
	if err != nil {
		t.Fatal(err)
	}
	if r.ran("/bin/git") || r.ran("/usr/bin/open") {
		t.Errorf("declining must not touch git or open: %v", r.calls)
	}
}

func TestSmokeChoiceOpensDeepLink(t *testing.T) {
	env := testEnv(t, "adr-review", "code-review")
	configPath := writeConfig(t, env, configJSON(
		choiceJSON("adr", "ADRレビュー", "adr-review"),
		choiceJSON("code", "コードレビュー", "code-review"),
	))
	cfg := mustConfig(t, env, mustRead(t, configPath))
	pr := PullRequest{Repo: "acme/app", Number: 12, HeadSHA: headSHA}
	path := worktreePath(cfg.WorktreeRoot, pr)
	checkout := cfg.Repositories["acme/app"]

	r := &fakeRunner{}
	r.reply("/bin/gh api", prJSON("acme/app", 12))
	r.reply("/bin/alerter", `{"activationType":"actionClicked","activationValue":"コードレビュー","activationValueIndex":"1"}`)
	r.reply("/bin/git -C "+checkout+" remote get-url origin", "git@github.com:acme/app.git\n")
	r.reply("/bin/git -C "+checkout+" cat-file", "")
	r.reply("/bin/git -C "+checkout+" worktree add", "")
	var link string
	r.on("/usr/bin/open", func(args []string) ([]byte, error) { link = args[0]; return nil, nil })

	var out bytes.Buffer
	if err := runSmoke(context.Background(), []string{"--config", configPath, "--pr", "https://github.com/acme/app/pull/12"}, env, r, &out); err != nil {
		t.Fatal(err)
	}
	u, err := url.Parse(link)
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	if q.Get("path") != path {
		t.Errorf("path = %q, want %q", q.Get("path"), path)
	}
	skill := filepath.Join(env.CodexHome, "skills", "code-review", "SKILL.md")
	want := "[$code-review](" + skill + ") https://github.com/acme/app/pull/12 " + headSHA + " " + path
	if q.Get("prompt") != want {
		t.Errorf("prompt = %q, want %q", q.Get("prompt"), want)
	}
}

func writeConfig(t *testing.T, env Env, data string) string {
	t.Helper()
	// Absolute command paths keep the smoke test away from whatever is installed on the machine.
	data = strings.Replace(data, `{"repositories"`, `{"commands":{"gh":"/bin/gh","git":"/bin/git","alerter":"/bin/alerter","open":"/usr/bin/open","osascript":"/usr/bin/osascript"},"repositories"`, 1)
	path := filepath.Join(env.Home, "config.json")
	if err := os.WriteFile(path, []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func mustRead(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestExampleConfigLoads(t *testing.T) {
	env := testEnv(t, "adr-review", "code-review")
	cfg, err := loadConfig("config.example.json", env)
	if err != nil {
		t.Fatal(err)
	}
	if len(cfg.Choices) != 2 {
		t.Errorf("choices = %d", len(cfg.Choices))
	}
}

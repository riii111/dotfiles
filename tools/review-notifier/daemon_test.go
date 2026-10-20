package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func searchJSON(items ...string) string {
	return `{"items":[` + strings.Join(items, ",") + `]}`
}

func searchItem(repo string, number int, updated string) string {
	return fmt.Sprintf(`{"number":%d,"title":"PR %d","updated_at":%q,"repository_url":"https://api.github.com/repos/%s"}`, number, number, updated, repo)
}

func requestedEvent(id int64, requester, reviewer string) string {
	return fmt.Sprintf(`{"id":%d,"event":"review_requested","review_requester":{"login":%q},"requested_reviewer":{"login":%q}}`, id, requester, reviewer)
}

func TestDecodePagesJoinsPaginatedArrays(t *testing.T) {
	events, err := decodePages([]byte(`[{"id":1,"event":"labeled"}]` + "\n" + `[{"id":2,"event":"review_requested"}]`))
	if err != nil || len(events) != 2 || events[1].ID != 2 {
		t.Fatalf("events = %+v, %v", events, err)
	}
}

func TestLatestRequestNamesTheRequesterNotTheAuthor(t *testing.T) {
	hit := searchHit{Repo: "acme/app", Number: 3, Title: "T"}
	events, _ := decodePages([]byte(`[` +
		requestedEvent(10, "tanaka", "me") + `,` +
		requestedEvent(11, "sato", "someone-else") + `,` +
		requestedEvent(12, "suzuki", "ME") + `,` +
		`{"id":13,"event":"commented"}]`))
	f, ok := latestRequest(events, hit, "me", nil)
	if !ok || f.Key != "acme/app#3@12" || f.Requester != "suzuki" {
		t.Fatalf("found = %+v %v", f, ok)
	}

	events, _ = decodePages([]byte(`[{"id":20,"event":"review_requested","requested_reviewer":{"login":"me"}}]`))
	if f, _ := latestRequest(events, hit, "me", nil); f.Requester != "" {
		t.Errorf("a missing requester must stay unknown, got %q", f.Requester)
	}
}

func TestLatestRequestOnlyCountsConfiguredTeams(t *testing.T) {
	hit := searchHit{Repo: "acme/app", Number: 3}
	events, _ := decodePages([]byte(`[
		{"id":1,"event":"review_requested","review_requester":{"login":"a"},"requested_team":{"slug":"backend"}},
		{"id":2,"event":"review_requested","review_requester":{"login":"b"},"requested_team":{"slug":"frontend"}}]`))
	f, ok := latestRequest(events, hit, "me", []string{"acme/backend"})
	if !ok || f.Key != "acme/app#3@1" || f.Team != "acme/backend" {
		t.Fatalf("found = %+v %v", f, ok)
	}
	if _, ok := latestRequest(events, hit, "me", []string{"other/backend"}); ok {
		t.Error("a team of another organization must not match")
	}
	if _, ok := latestRequest(events, hit, "me", nil); ok {
		t.Error("team requests must not match without configured teams")
	}
}

func TestPendingRequestsReadsEventsOnlyForUpdatedPRs(t *testing.T) {
	r := &fakeRunner{}
	updated := "2026-10-20T10:00:00Z"
	r.on("gh api -X GET search/issues", func([]string) ([]byte, error) {
		return []byte(searchJSON(searchItem("acme/app", 3, updated))), nil
	})
	r.reply("gh api --paginate repos/acme/app/issues/3/events", `[`+requestedEvent(7, "tanaka", "me")+`]`)

	found, cache, err := pendingRequests(context.Background(), r, "gh", "me", nil, nil)
	if err != nil || len(found) != 1 || found[0].Key != "acme/app#3@7" {
		t.Fatalf("found = %+v, %v", found, err)
	}
	r.calls = nil
	if _, _, err := pendingRequests(context.Background(), r, "gh", "me", nil, cache); err != nil {
		t.Fatal(err)
	}
	if r.ran("gh api --paginate") {
		t.Error("events of an unchanged PR must come from the cache")
	}
	updated = "2026-10-20T11:00:00Z"
	if _, _, err := pendingRequests(context.Background(), r, "gh", "me", nil, cache); err != nil {
		t.Fatal(err)
	}
	if !r.ran("gh api --paginate") {
		t.Error("events of an updated PR must be read again")
	}
}

func TestPendingRequestsQueriesConfiguredTeams(t *testing.T) {
	r := &fakeRunner{}
	r.reply("gh api -X GET search/issues", searchJSON())
	if _, _, err := pendingRequests(context.Background(), r, "gh", "me", []string{"acme/backend"}, nil); err != nil {
		t.Fatal(err)
	}
	if !r.ran("gh api -X GET search/issues -f q=is:pr is:open archived:false user-review-requested:@me") ||
		!r.ran("gh api -X GET search/issues -f q=is:pr is:open archived:false team-review-requested:acme/backend") {
		t.Errorf("calls = %v", r.calls)
	}
}

func found(repo string, number int, id int64) Found {
	return Found{Key: fmt.Sprintf("%s#%d@%d", repo, number, id), Repo: repo, Number: number, Title: "T"}
}

func TestApplyPollBaselineAndDedupe(t *testing.T) {
	st := newState()
	now := time.Date(2026, 10, 20, 9, 0, 0, 0, time.UTC)
	if added := st.applyPoll([]Found{found("acme/app", 1, 10)}, now, true); len(added) != 0 {
		t.Fatalf("baseline added %v", added)
	}
	if st.nextQueued() != nil {
		t.Fatal("baseline requests must not be queued")
	}

	added := st.applyPoll([]Found{found("acme/app", 1, 10), found("acme/app", 2, 20)}, now, false)
	if len(added) != 1 || added[0] != "acme/app#2@20" {
		t.Fatalf("added = %v", added)
	}
	st.Requests["acme/app#2@20"].Status = StatusDeclined
	if added := st.applyPoll([]Found{found("acme/app", 1, 10), found("acme/app", 2, 20)}, now, false); len(added) != 0 {
		t.Errorf("a declined request was added again: %v", added)
	}
	// A re-request of the same PR is a new event.
	if added := st.applyPoll([]Found{found("acme/app", 2, 21)}, now, false); len(added) != 1 || added[0] != "acme/app#2@21" {
		t.Errorf("re-request added = %v", added)
	}
}

func TestApplyPollWithdrawsAndRequeues(t *testing.T) {
	st := newState()
	now := time.Now()
	st.applyPoll([]Found{found("acme/app", 1, 10)}, now, false)
	st.applyPoll(nil, now, false)
	if got := st.Requests["acme/app#1@10"].Status; got != StatusWithdrawn {
		t.Fatalf("status = %s", got)
	}
	st.applyPoll([]Found{found("acme/app", 1, 10)}, now, false)
	if got := st.Requests["acme/app#1@10"].Status; got != StatusQueued {
		t.Fatalf("status = %s", got)
	}
}

func TestApplyPollPrunesOldFinishedRequests(t *testing.T) {
	st := newState()
	old := time.Now().Add(-retention - time.Hour)
	st.applyPoll([]Found{found("acme/app", 1, 10)}, old, false)
	st.Requests["acme/app#1@10"].Status = StatusLaunched
	st.applyPoll(nil, time.Now(), false)
	if _, ok := st.Requests["acme/app#1@10"]; ok {
		t.Error("an old finished request must be pruned")
	}
}

func TestRecoverNeverRepeatsALaunch(t *testing.T) {
	st := newState()
	st.applyPoll([]Found{found("acme/app", 1, 10), found("acme/app", 2, 20)}, time.Now(), false)
	st.Requests["acme/app#1@10"].Status = StatusNotifying
	st.Requests["acme/app#2@20"].Status = StatusLaunching
	st.recover(time.Now())
	if got := st.Requests["acme/app#1@10"].Status; got != StatusQueued {
		t.Errorf("notifying became %s", got)
	}
	if got := st.Requests["acme/app#2@20"].Status; got != StatusFailed {
		t.Errorf("launching became %s", got)
	}
}

func TestStoreRoundTripAndLock(t *testing.T) {
	dir := t.TempDir()
	store := Store{path: filepath.Join(dir, "state.json")}
	st, ok, err := store.Load()
	if err != nil || ok {
		t.Fatalf("fresh load: %v %v", ok, err)
	}
	st.applyPoll([]Found{found("acme/app", 1, 10)}, time.Now(), false)
	if err := store.Save(st); err != nil {
		t.Fatal(err)
	}
	loaded, ok, err := store.Load()
	if err != nil || !ok || loaded.Requests["acme/app#1@10"].Status != StatusQueued {
		t.Fatalf("loaded = %+v, %v", loaded, err)
	}

	lock, err := lockDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := lockDir(dir); err == nil {
		t.Error("a second instance must not get the lock")
	}
	lock.Close()
	again, err := lockDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	again.Close()
}

// daemonFixture wires a daemon to a fake GitHub whose pending requests the test changes between polls.
type daemonFixture struct {
	d       *Daemon
	r       *fakeRunner
	mu      sync.Mutex
	events  map[string]string // "repo#n" -> events JSON
	alerter string
	store   Store
	opened  []string
}

func newDaemonFixture(t *testing.T) *daemonFixture {
	env := testEnv(t, "code-review")
	cfg := mustConfig(t, env, configJSON(choiceJSON("code", "コードレビュー", "code-review")))
	f := &daemonFixture{r: &fakeRunner{}, events: map[string]string{}}
	f.r.reply("gh api user", `{"login":"me"}`)
	f.r.on("gh api -X GET search/issues", func(args []string) ([]byte, error) {
		f.mu.Lock()
		defer f.mu.Unlock()
		var items []string
		for k, ev := range f.events {
			repo, num, _ := strings.Cut(k, "#")
			var n int
			fmt.Sscan(num, &n)
			items = append(items, searchItem(repo, n, fmt.Sprintf("%x", len(ev))))
		}
		return []byte(searchJSON(items...)), nil
	})
	f.r.on("gh api --paginate", func(args []string) ([]byte, error) {
		f.mu.Lock()
		defer f.mu.Unlock()
		for k, ev := range f.events {
			repo, num, _ := strings.Cut(k, "#")
			if strings.Contains(args[2], "repos/"+repo+"/issues/"+num+"/") {
				return []byte(ev), nil
			}
		}
		return nil, fmt.Errorf("no events for %v", args)
	})
	f.r.on("gh api repos/", func(args []string) ([]byte, error) {
		parts := strings.Split(args[1], "/")
		var n int
		fmt.Sscan(parts[4], &n)
		return []byte(prJSON(parts[1]+"/"+parts[2], n)), nil
	})
	f.r.on("alerter", func([]string) ([]byte, error) { return []byte(f.alerter), nil })
	checkout := cfg.Repositories["acme/app"]
	f.r.reply("git -C "+checkout+" remote get-url origin", "git@github.com:acme/app.git\n")
	f.r.reply("git -C "+checkout+" cat-file", "")
	f.r.reply("git -C "+checkout+" worktree add", "")
	f.r.on("open", func(args []string) ([]byte, error) { f.opened = append(f.opened, args[0]); return nil, nil })
	f.r.reply("osascript", "")

	f.store = Store{path: filepath.Join(t.TempDir(), "state.json")}
	st, _, _ := f.store.Load()
	tools := Tools{R: f.r, Cmds: Commands{GH: "gh", Git: "git", Alerter: "alerter", Open: "open", Osascript: "osascript"}, Cfg: cfg}
	f.d = newDaemon(tools, f.store, st, log.New(io.Discard, "", 0))
	f.d.sleep = func(context.Context, time.Duration) error { return nil }
	return f
}

func (f *daemonFixture) request(repo string, number int, events ...string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.events[fmt.Sprintf("%s#%d", repo, number)] = "[" + strings.Join(events, ",") + "]"
}

func (f *daemonFixture) status(t *testing.T, key string) Status {
	t.Helper()
	st, _, err := f.store.Load()
	if err != nil {
		t.Fatal(err)
	}
	req, ok := st.Requests[key]
	if !ok {
		t.Fatalf("%s not in state", key)
	}
	return req.Status
}

func TestDaemonNotifiesOnlyNewRequestsAndLaunchesTheChoice(t *testing.T) {
	f := newDaemonFixture(t)
	ctx := context.Background()
	f.request("acme/app", 1, requestedEvent(10, "tanaka", "me"))
	if err := f.d.pollOnce(ctx); err != nil {
		t.Fatal(err)
	}
	if f.d.handleNext(ctx) {
		t.Fatal("the first poll is only a baseline")
	}

	f.request("acme/app", 12, requestedEvent(30, "sato", "me"))
	if err := f.d.pollOnce(ctx); err != nil {
		t.Fatal(err)
	}
	f.alerter = `{"activationType":"actionClicked","activationValue":"コードレビュー"}`
	if !f.d.handleNext(ctx) {
		t.Fatal("the new request must be notified")
	}
	if got := f.status(t, "acme/app#12@30"); got != StatusLaunched {
		t.Fatalf("status = %s", got)
	}
	if len(f.opened) != 1 || !strings.HasPrefix(f.opened[0], "codex://new?prompt=") {
		t.Fatalf("opened = %v", f.opened)
	}
	if f.d.handleNext(ctx) {
		t.Error("nothing else is queued")
	}

	// Restart: the saved state carries over, so nothing is notified again.
	st, _, _ := f.store.Load()
	f.d.st = st
	if err := f.d.pollOnce(ctx); err != nil {
		t.Fatal(err)
	}
	if f.d.handleNext(ctx) || len(f.opened) != 1 {
		t.Error("a launched request must not be notified or opened again")
	}
}

func TestDaemonDeclineAndTimeoutStartNothing(t *testing.T) {
	f := newDaemonFixture(t)
	ctx := context.Background()
	if err := f.d.pollOnce(ctx); err != nil {
		t.Fatal(err)
	}
	f.request("acme/app", 1, requestedEvent(10, "tanaka", "me"))
	f.request("acme/app", 2, requestedEvent(20, "tanaka", "me"))
	if err := f.d.pollOnce(ctx); err != nil {
		t.Fatal(err)
	}
	f.alerter = `{"activationType":"closed","activationValue":"見送る"}`
	f.d.handleNext(ctx)
	f.alerter = `{"activationType":"timeout"}`
	f.d.handleNext(ctx)
	if f.status(t, "acme/app#1@10") != StatusDeclined || f.status(t, "acme/app#2@20") != StatusTimeout {
		t.Error("unexpected statuses")
	}
	if f.r.ran("git") || len(f.opened) != 0 {
		t.Error("nothing may be started")
	}
	if err := f.d.pollOnce(ctx); err != nil {
		t.Fatal(err)
	}
	if f.d.handleNext(ctx) {
		t.Error("declined and timed-out requests must not be shown again")
	}
}

func TestDaemonReportsALaunchFailure(t *testing.T) {
	f := newDaemonFixture(t)
	ctx := context.Background()
	if err := f.d.pollOnce(ctx); err != nil {
		t.Fatal(err)
	}
	f.request("acme/unknown", 5, requestedEvent(50, "tanaka", "me"))
	if err := f.d.pollOnce(ctx); err != nil {
		t.Fatal(err)
	}
	f.alerter = `{"activationType":"actionClicked","activationValue":"コードレビュー"}`
	f.d.handleNext(ctx)
	if got := f.status(t, "acme/unknown#5@50"); got != StatusFailed {
		t.Fatalf("status = %s", got)
	}
	if !f.r.ran("osascript") || len(f.opened) != 0 {
		t.Error("the failure must be notified without opening anything")
	}
}

func TestDaemonKeepsPollingAfterAnAPIFailure(t *testing.T) {
	f := newDaemonFixture(t)
	f.r.handlers = append([]handler{{"gh api -X GET search/issues", func([]string) ([]byte, error) {
		return nil, fmt.Errorf("HTTP 403: API rate limit exceeded")
	}}}, f.r.handlers...)
	ctx, cancel := context.WithCancel(context.Background())
	polls := 0
	f.d.sleep = func(_ context.Context, d time.Duration) error {
		polls++
		if polls == 1 && d != 2*time.Minute {
			t.Errorf("first backoff = %s", d)
		}
		if polls == 3 {
			cancel()
			return context.Canceled
		}
		return nil
	}
	f.d.pollLoop(ctx)
	if polls != 3 {
		t.Errorf("polls = %d", polls)
	}
	st, _, _ := f.store.Load()
	if !strings.Contains(st.LastError, "rate limit") {
		t.Errorf("last error = %q", st.LastError)
	}
}

func TestBackoffIsBounded(t *testing.T) {
	if got := backoff(time.Minute, 1); got != 2*time.Minute {
		t.Errorf("backoff(1) = %s", got)
	}
	if got := backoff(time.Minute, 20); got != maxBackoff {
		t.Errorf("backoff(20) = %s", got)
	}
}

func TestMain(m *testing.M) {
	// State and config paths must never fall back to the real home in tests.
	os.Setenv("XDG_STATE_HOME", "")
	os.Setenv("XDG_CONFIG_HOME", "")
	os.Exit(m.Run())
}

func TestDaemonRunNotifiesWhilePollingAndStops(t *testing.T) {
	f := newDaemonFixture(t)
	f.alerter = `{"activationType":"closed"}`
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	polls := 0
	f.d.sleep = func(ctx context.Context, _ time.Duration) error {
		polls++
		if polls == 1 {
			f.request("acme/app", 1, requestedEvent(10, "tanaka", "me"))
			return nil
		}
		// Waits until the notification of the second poll was answered, then stops.
		for i := 0; i < 200; i++ {
			st, _, _ := f.store.Load()
			if req, ok := st.Requests["acme/app#1@10"]; ok && req.Status == StatusDeclined {
				cancel()
				return context.Canceled
			}
			time.Sleep(5 * time.Millisecond)
		}
		cancel()
		return context.Canceled
	}
	done := make(chan error)
	go func() { done <- f.d.Run(ctx) }()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not stop")
	}
	if got := f.status(t, "acme/app#1@10"); got != StatusDeclined {
		t.Errorf("status = %s", got)
	}
}

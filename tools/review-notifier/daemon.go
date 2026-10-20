package main

import (
	"context"
	"errors"
	"log"
	"maps"
	"strconv"
	"sync"
	"time"
)

const maxBackoff = 15 * time.Minute

// Polling and notifying run separately, so a notification waiting for the user never delays the next poll.
// Notifications are shown one at a time from the queue in the state.
type Daemon struct {
	tools Tools
	store Store
	log   *log.Logger
	now   func() time.Time
	sleep func(context.Context, time.Duration) error

	mu   sync.Mutex
	st   *State
	wake chan struct{}
}

func newDaemon(t Tools, store Store, st *State, logger *log.Logger) *Daemon {
	return &Daemon{
		tools: t,
		store: store,
		st:    st,
		log:   logger,
		now:   time.Now,
		sleep: sleepCtx,
		wake:  make(chan struct{}, 1),
	}
}

func sleepCtx(ctx context.Context, d time.Duration) error {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

func (d *Daemon) Run(ctx context.Context) error {
	d.mu.Lock()
	d.st.recover(d.now())
	err := d.store.Save(d.st)
	d.mu.Unlock()
	if err != nil {
		return err
	}

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		d.notifyLoop(ctx)
	}()
	d.pollLoop(ctx)
	wg.Wait()
	return nil
}

func (d *Daemon) pollLoop(ctx context.Context) {
	interval := time.Duration(d.tools.Cfg.PollIntervalSeconds) * time.Second
	failures := 0
	for {
		delay := interval
		if err := d.pollOnce(ctx); err != nil {
			if ctx.Err() != nil {
				return
			}
			failures++
			delay = backoff(interval, failures)
			d.log.Printf("poll failed (%d in a row, next in %s): %v", failures, delay, err)
		} else {
			failures = 0
		}
		if d.sleep(ctx, delay) != nil {
			return
		}
	}
}

// Rate limits and outages are waited out with a growing delay instead of stopping the watcher.
func backoff(interval time.Duration, failures int) time.Duration {
	delay := interval
	for i := 0; i < failures && delay < maxBackoff; i++ {
		delay *= 2
	}
	return min(delay, maxBackoff)
}

func (d *Daemon) pollOnce(ctx context.Context) error {
	d.mu.Lock()
	login := d.st.Login
	cache := maps.Clone(d.st.PRs)
	d.mu.Unlock()

	t := d.tools
	if login == "" {
		var err error
		if login, err = currentLogin(ctx, t.R, t.Cmds.GH); err != nil {
			return d.recordError(err)
		}
	}
	found, next, err := pendingRequests(ctx, t.R, t.Cmds.GH, login, t.Cfg.Teams, cache)
	if err != nil {
		return d.recordError(err)
	}

	d.mu.Lock()
	baseline := d.st.LastPoll.IsZero() && len(d.st.Requests) == 0
	added := d.st.applyPoll(found, d.now(), baseline)
	d.st.Login, d.st.PRs, d.st.LastPoll, d.st.LastError = login, next, d.now(), ""
	err = d.store.Save(d.st)
	d.mu.Unlock()
	if err != nil {
		return err
	}
	if baseline {
		d.log.Printf("recorded %d pending requests as the baseline; only later requests are notified", len(found))
	}
	for _, key := range added {
		d.log.Printf("new request %s", key)
	}
	d.signal()
	return nil
}

func (d *Daemon) recordError(err error) error {
	d.mu.Lock()
	d.st.LastError = err.Error()
	if saveErr := d.store.Save(d.st); saveErr != nil {
		err = errors.Join(err, saveErr)
	}
	d.mu.Unlock()
	return err
}

func (d *Daemon) signal() {
	select {
	case d.wake <- struct{}{}:
	default:
	}
}

func (d *Daemon) notifyLoop(ctx context.Context) {
	for ctx.Err() == nil {
		if d.handleNext(ctx) {
			continue
		}
		select {
		case <-ctx.Done():
			return
		case <-d.wake:
		}
	}
}

// Shows the oldest queued request and acts on the answer. Reports whether there was one.
func (d *Daemon) handleNext(ctx context.Context) bool {
	d.mu.Lock()
	req := d.st.nextQueued()
	if req == nil {
		d.mu.Unlock()
		return false
	}
	req.Status, req.UpdatedAt = StatusNotifying, d.now()
	snapshot := *req
	err := d.store.Save(d.st)
	d.mu.Unlock()
	if err != nil {
		d.log.Printf("save state: %v", err)
		return false
	}

	t := d.tools
	notice := Notice{Key: snapshot.Key, PR: PullRequest{Repo: snapshot.Repo, Number: snapshot.Number, Title: snapshot.Title}, Requester: snapshot.Requester, Team: snapshot.Team}
	sel, err := notify(ctx, t.R, t.Cmds.Alerter, notice, t.Cfg.Choices, t.Cfg.NotificationTimeoutSeconds)
	if ctx.Err() != nil {
		// Stopping: the request stays notifying and is shown again after the restart.
		return false
	}
	if err != nil {
		d.log.Printf("notify %s: %v", snapshot.Key, err)
		d.update(snapshot.Key, func(r *Request) { r.Status, r.Error = StatusQueued, err.Error() })
		// Retried after a poll interval rather than in a tight loop.
		_ = d.sleep(ctx, time.Duration(t.Cfg.PollIntervalSeconds)*time.Second)
		return true
	}

	switch sel.Outcome {
	case Declined:
		d.update(snapshot.Key, func(r *Request) { r.Status = StatusDeclined })
	case TimedOut:
		d.update(snapshot.Key, func(r *Request) { r.Status = StatusTimeout })
	case Dismissed:
		d.update(snapshot.Key, func(r *Request) { r.Status = StatusDismissed })
	case Chosen:
		d.launch(ctx, snapshot, sel.Choice)
		return true
	}
	d.log.Printf("%s: %s", snapshot.Key, sel.Outcome)
	return true
}

func (d *Daemon) launch(ctx context.Context, req Request, ch *Choice) {
	// Recorded before anything is opened, so a restart never opens the same request twice.
	if !d.update(req.Key, func(r *Request) { r.Status, r.Choice, r.Error = StatusLaunching, ch.ID, "" }) {
		return
	}
	d.log.Printf("%s: chose %s", req.Key, ch.ID)
	res, err := launch(ctx, d.tools, ch, req.Repo, req.Number, req.Requester)
	d.update(req.Key, func(r *Request) {
		r.HeadSHA, r.Worktree = res.PR.HeadSHA, res.Worktree
		if err != nil {
			r.Status, r.Error = StatusFailed, err.Error()
		} else {
			r.Status = StatusLaunched
		}
	})
	if err != nil {
		d.log.Printf("%s: launch failed: %v", req.Key, err)
		if nerr := notifyFailure(ctx, d.tools.R, d.tools.Cmds.Osascript, req.Repo+" #"+strconv.Itoa(req.Number), "レビューを開始できませんでした: "+err.Error()); nerr != nil {
			d.log.Printf("%s: failure notification: %v", req.Key, nerr)
		}
		return
	}
	d.log.Printf("%s: opened %s at %s", req.Key, res.Worktree, res.PR.HeadSHA)
}

func (d *Daemon) update(key string, change func(*Request)) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	req, ok := d.st.Requests[key]
	if !ok {
		return false
	}
	change(req)
	req.UpdatedAt = d.now()
	if err := d.store.Save(d.st); err != nil {
		d.log.Printf("save state: %v", err)
	}
	return true
}

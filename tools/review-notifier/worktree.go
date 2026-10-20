package main

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var githubRemote = regexp.MustCompile(`^(?:https://github\.com/|ssh://git@github\.com/|git@github\.com:)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?$`)

func remoteRepo(remote string) (string, bool) {
	m := githubRemote.FindStringSubmatch(strings.TrimSpace(remote))
	if m == nil {
		return "", false
	}
	return m[1], true
}

func worktreePath(root string, pr PullRequest) string {
	owner, name, _ := strings.Cut(pr.Repo, "/")
	return filepath.Join(root, owner, name, fmt.Sprintf("pr-%d-%s", pr.Number, pr.HeadSHA[:12]))
}

// Creates a detached worktree at the PR head, or returns the one an earlier selection created.
// Only objects are fetched into the checkout; its branches, HEAD and working tree are left alone.
func prepareWorktree(ctx context.Context, r Runner, git string, cfg *Config, pr PullRequest) (string, error) {
	checkout, ok := lookupRepo(cfg.Repositories, pr.Repo)
	if !ok {
		return "", fmt.Errorf("%s has no local checkout in repositories of the config", pr.Repo)
	}
	out, err := r.Run(ctx, git, "-C", checkout, "remote", "get-url", "origin")
	if err != nil {
		return "", err
	}
	if got, ok := remoteRepo(string(out)); !ok || !strings.EqualFold(got, pr.Repo) {
		return "", fmt.Errorf("%s: origin %q is not %s", checkout, strings.TrimSpace(string(out)), pr.Repo)
	}

	path := worktreePath(cfg.WorktreeRoot, pr)
	if _, err := os.Stat(path); err == nil {
		head, err := r.Run(ctx, git, "-C", path, "rev-parse", "HEAD")
		if err != nil {
			return "", fmt.Errorf("%s exists but is not a worktree: %w", path, err)
		}
		if strings.TrimSpace(string(head)) != pr.HeadSHA {
			return "", fmt.Errorf("%s exists at %s, not %s", path, strings.TrimSpace(string(head)), pr.HeadSHA)
		}
		return path, nil
	} else if !errors.Is(err, fs.ErrNotExist) {
		return "", err
	}

	commit := pr.HeadSHA + "^{commit}"
	if _, err := r.Run(ctx, git, "-C", checkout, "cat-file", "-e", commit); err != nil {
		// The pull ref also serves heads from forks; the SHA itself covers a PR that moved on since it was read.
		fetched := false
		for _, ref := range []string{fmt.Sprintf("refs/pull/%d/head", pr.Number), pr.HeadSHA} {
			if _, err := r.Run(ctx, git, "-C", checkout, "fetch", "--no-tags", "--no-write-fetch-head", "origin", ref); err != nil {
				continue
			}
			if _, err := r.Run(ctx, git, "-C", checkout, "cat-file", "-e", commit); err == nil {
				fetched = true
				break
			}
		}
		if !fetched {
			return "", fmt.Errorf("%s: cannot fetch %s", checkout, pr.HeadSHA)
		}
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return "", err
	}
	if _, err := r.Run(ctx, git, "-C", checkout, "worktree", "add", "--detach", path, pr.HeadSHA); err != nil {
		return "", err
	}
	return path, nil
}

func lookupRepo(repos map[string]string, repo string) (string, bool) {
	for name, path := range repos {
		if strings.EqualFold(name, repo) {
			return path, true
		}
	}
	return "", false
}

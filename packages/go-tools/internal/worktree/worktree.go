// Package worktree reads what the slop tools take from the checkout they run
// in: the Gerrit project it came from, and the topic, which is named for the
// worktree so that each session's changes are one topic.
package worktree

import (
	"fmt"
	"net/url"
	"os/exec"
	"path/filepath"
	"strings"
)

func Topic() (project, topic string, err error) {
	root, err := git("rev-parse", "--show-toplevel")
	if err != nil {
		return "", "", fmt.Errorf("finding the worktree: %w", err)
	}
	remote, err := git("remote", "get-url", "origin")
	if err != nil {
		return "", "", fmt.Errorf("finding the Gerrit project: %w", err)
	}
	project, err = projectFromURL(remote)
	if err != nil {
		return "", "", err
	}
	return project, filepath.Base(root), nil
}

func projectFromURL(remote string) (string, error) {
	parsed, err := url.Parse(remote)
	if err != nil {
		return "", fmt.Errorf("parsing remote URL %q: %w", remote, err)
	}
	project := strings.TrimSuffix(strings.Trim(parsed.Path, "/"), ".git")
	if parsed.Host == "" || project == "" {
		return "", fmt.Errorf("remote URL %q doesn't name a Gerrit project", remote)
	}
	return project, nil
}

func git(args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("git %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return strings.TrimSpace(string(out)), nil
}

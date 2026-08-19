// slop-pr proposes the current branch as a Gerrit change, so that no branch is
// created and re-running adds a patch set to the existing change.
// See design_docs/gerrit.md.
package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/bjackman/boxen/slop-tools/internal/gerrit"
)

// Set at build time; the defaults are only useful for `go run`.
var (
	gerritHost   = "pizza"
	gerritPort   = "29418"
	gerritURL    = "https://gerrit.home.yawn.io"
	pusher       = "slopbot"
	reviewer     = "brendan"
	branch       = "master"
	keyFile      = "/run/agenix/slopbot-ssh-privkey"
	authUser     = "slopbot"
	passwordFile = "/run/agenix/slopbot-authelia-password"
)

// publishedError is a failure after the change reached the forge, where
// reporting it as a plain failure would suggest nothing had been pushed.
type publishedError struct {
	url string
	err error
}

func (e *publishedError) Error() string { return e.err.Error() }
func (e *publishedError) Unwrap() error { return e.err }

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "slop-pr: %v\n", err)
		var published *publishedError
		if errors.As(err, &published) {
			fmt.Fprintf(os.Stderr, "slop-pr: the change was pushed: %s\n", published.url)
		}
		os.Exit(exitCode(err))
	}
}

// A failure after the push leaves a change behind that just needs finishing,
// which is a different thing to fix than a failure to publish at all.
func exitCode(err error) int {
	var published *publishedError
	if errors.As(err, &published) {
		return 2
	}
	return 1
}

func run() error {
	root, err := git("rev-parse", "--show-toplevel")
	if err != nil {
		return err
	}
	topic := filepath.Base(root)
	project := filepath.Base(filepath.Dir(root))

	if err := push(topic); err != nil {
		return err
	}

	port, err := strconv.Atoi(gerritPort)
	if err != nil {
		return fmt.Errorf("bad gerritPort %q: %w", gerritPort, err)
	}
	client, err := gerrit.NewClient(gerrit.Config{
		Host: gerritHost, Port: port, User: pusher, KeyFile: keyFile,
		BaseURL: gerritURL, AuthUser: authUser, PasswordFile: passwordFile,
	})
	if err != nil {
		return err
	}
	changes, err := client.Query("status:open", "project:"+project, "topic:"+topic)
	if err != nil {
		return err
	}
	if len(changes) == 0 {
		return fmt.Errorf("pushed, but no open change has topic %q in %s", topic, project)
	}
	for _, change := range changes {
		fmt.Println(change.URL)
	}
	return nil
}

// push sends every commit not yet on the branch as one topic. Gerrit rejects a
// push whose commits it already has, which is success as far as this is
// concerned: the change is published either way.
func push(topic string) error {
	args := []string{
		"push", "origin", "HEAD:refs/for/" + branch,
		"-o", "topic=" + topic,
		"-o", "r=" + reviewer,
	}
	cmd := exec.Command("git", args...)
	var stderr strings.Builder
	// Gerrit reports the change URL on stderr, so let it through as well as
	// capturing it.
	cmd.Stdout = os.Stderr
	cmd.Stderr = io.MultiWriter(os.Stderr, &stderr)
	if err := cmd.Run(); err != nil {
		if strings.Contains(stderr.String(), "no new changes") {
			return nil
		}
		return fmt.Errorf("git push: %w", err)
	}
	return nil
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

// slop-pr proposes the current branch as a Forgejo pull request, using AGit so
// that no branch is created and re-running adds a version to the existing
// request. See design_docs/agent_prs.md.
package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/bjackman/boxen/slop-tools/internal/forgejo"
)

// Set at build time; the defaults are only useful for `go run`.
var (
	forgejoURL   = "https://forgejo.home.yawn.io"
	owner        = "brendan"
	pusher       = "slopbot"
	passwordFile = "/run/agenix/slopbot-forgejo-password"
)

const agentLabel = "agent"

// publishedError is a failure after the change reached the forge, where
// reporting it as a plain failure would suggest nothing had been pushed.
type publishedError struct {
	url string
	err error
}

func (e *publishedError) Error() string { return e.err.Error() }
func (e *publishedError) Unwrap() error { return e.err }

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "slop-pr: %v\n", err)
		var published *publishedError
		if errors.As(err, &published) {
			fmt.Fprintf(os.Stderr, "slop-pr: the change was pushed: %s\n", published.url)
		}
		os.Exit(exitCode(err))
	}
}

// A failure after the push leaves a pull request behind that just needs
// finishing, which is a different thing to fix than a failure to publish at
// all.
func exitCode(err error) int {
	var published *publishedError
	if errors.As(err, &published) {
		return 2
	}
	return 1
}

func run(args []string) error {
	if len(args) > 1 {
		return fmt.Errorf("usage: slop-pr [title]")
	}

	root, err := git("rev-parse", "--show-toplevel")
	if err != nil {
		return err
	}
	topic := filepath.Base(root)
	repo := filepath.Base(filepath.Dir(root))

	client, err := forgejo.NewClient(forgejoURL, pusher, passwordFile)
	if err != nil {
		return err
	}

	pr, err := client.FindPullByTopic(owner, repo, topic)
	if err != nil {
		return err
	}

	head, err := git("rev-parse", "HEAD")
	if err != nil {
		return err
	}

	switch {
	case pr == nil:
		title, err := title(args)
		if err != nil {
			return err
		}
		if err := push(topic, title); err != nil {
			return err
		}
		if pr, err = client.FindPullByTopic(owner, repo, topic); err != nil {
			return err
		}
		if pr == nil {
			return fmt.Errorf("pushed, but no pull request appeared for topic %q", topic)
		}
	case pr.Head.SHA != head:
		// Forgejo rejects a push whose head the pull request already has, and
		// the title is deliberately not resent: it may have been edited in the
		// web UI.
		if err := push(topic, ""); err != nil {
			return err
		}
		if pr, err = client.Pull(owner, repo, pr.Number); err != nil {
			return err
		}
	}

	url := fmt.Sprintf("%s/%s/%s/pulls/%d", forgejoURL, owner, repo, pr.Number)

	if err := ensureLabel(client, repo, pr); err != nil {
		return &publishedError{url: url, err: err}
	}
	if err := ensureAssignee(client, repo, pr); err != nil {
		return &publishedError{url: url, err: err}
	}

	fmt.Println(url)
	return nil
}

// title defaults to the subject of the first commit of the change, which
// describes it better than the most recent one does.
func title(args []string) (string, error) {
	if len(args) == 1 {
		return args[0], nil
	}
	subjects, err := git("log", "--format=%s", "origin/master..HEAD")
	if err != nil {
		return "", err
	}
	lines := strings.Split(strings.TrimSpace(subjects), "\n")
	if len(lines) == 0 || lines[0] == "" {
		return "", fmt.Errorf("no commits on top of origin/master to describe")
	}
	return lines[len(lines)-1], nil
}

func ensureLabel(client *forgejo.Client, repo string, pr *forgejo.PullRequest) error {
	if pr.HasLabel(agentLabel) {
		return nil
	}
	labels, err := client.Labels(owner, repo)
	if err != nil {
		return err
	}
	for _, label := range labels {
		if label.Name == agentLabel {
			return client.AddLabel(owner, repo, pr.Number, label.ID)
		}
	}
	return fmt.Errorf("no %q label in %s/%s; is forgejo-bootstrap.service healthy?", agentLabel, owner, repo)
}

func ensureAssignee(client *forgejo.Client, repo string, pr *forgejo.PullRequest) error {
	logins := pr.AssigneeLogins()
	for _, login := range logins {
		if login == owner {
			return nil
		}
	}
	return client.SetAssignees(owner, repo, pr.Number, append(logins, owner))
}

func push(topic, title string) error {
	args := []string{
		"push", "origin", "HEAD:refs/for/master",
		"-o", "topic=" + topic,
		"-o", "force-push=true",
	}
	if title != "" {
		args = append(args, "-o", "title="+title)
	}
	cmd := exec.Command("git", args...)
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
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

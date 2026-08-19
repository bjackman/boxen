// slop-handler drives an agent from Gerrit review comments, so that reviewing a
// change needs nothing but the forge. See design_docs/gerrit.md.
//
// Gerrit's event stream only wakes it up; the work is always to reconcile
// against the API. A dropped stream, a restart, or a topic deferred because a
// human was attached all recover on the next sweep, and there's one code path
// rather than two.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/bjackman/boxen/slop-tools/internal/gerrit"
	"github.com/bjackman/boxen/slop-tools/internal/session"
)

// Set at build time.
var (
	gerritHost   = "pizza"
	gerritPort   = "29418"
	gerritURL    = "https://gerrit.home.yawn.io"
	pusher       = "slopbot"
	reviewer     = "brendan"
	keyFile      = "/run/agenix/slopbot-ssh-privkey"
	authUser     = "slopbot"
	passwordFile = "/run/agenix/slopbot-authelia-password"
)

var (
	stateDir = flag.String("state-dir", "/var/lib/slop-handler",
		"where to record which comments have been handled")
	sweepFreq = flag.Duration("sweep", 5*time.Minute,
		"how often to reconcile against the API regardless of events")
	debounce = flag.Duration("debounce", 2*time.Minute,
		"how long a topic must be quiet before acting, so that reviewing a series is one run")
	runLimit = flag.Duration("run-limit", 30*time.Minute, "how long a single agent run may take")
	once     = flag.Bool("once", false, "sweep once and exit, rather than watching")
)

func main() {
	flag.Parse()
	log.SetFlags(0)
	if err := run(); err != nil {
		log.Fatalf("slop-handler: %v", err)
	}
}

func run() error {
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
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	h := &handler{client: client, home: home, statePath: filepath.Join(*stateDir, "handled.json")}
	if err := h.loadState(); err != nil {
		return err
	}

	if *once {
		_, err := h.sweep(context.Background())
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// Buffered so a burst of events collapses into one pending sweep.
	wake := make(chan struct{}, 1)
	go watch(ctx, client, wake)

	ticker := time.NewTicker(*sweepFreq)
	defer ticker.Stop()

	for {
		wait, err := h.sweep(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			log.Printf("sweep failed: %v", err)
		}

		// A topic held for the debounce needs waking when it ages out, or the
		// effective latency is the sweep interval rather than the window.
		var held <-chan time.Time
		if wait > 0 {
			timer := time.NewTimer(wait)
			defer timer.Stop()
			held = timer.C
		}

		select {
		case <-ctx.Done():
			return nil
		case <-wake:
		case <-ticker.C:
		case <-held:
		}
	}
}

// watch follows Gerrit's event stream, which is a long-lived SSH connection and
// so can die quietly. Nothing depends on it being up: it only saves waiting for
// the next sweep.
func watch(ctx context.Context, client *gerrit.Client, wake chan<- struct{}) {
	for ctx.Err() == nil {
		err := client.StreamEvents(ctx, func(event gerrit.Event) {
			if event.Type != "comment-added" {
				return
			}
			log.Printf("comment on change %d, sweeping", event.Change.Number)
			select {
			case wake <- struct{}{}:
			default:
			}
		})
		if ctx.Err() != nil {
			return
		}
		log.Printf("event stream stopped (%v), reconnecting", err)
		select {
		case <-ctx.Done():
		case <-time.After(30 * time.Second):
		}
	}
}

type handler struct {
	client    *gerrit.Client
	home      string
	statePath string
	// Handled comment ids, keyed by "<project>~<change number>". Gerrit's
	// comment ids are opaque strings.
	handled map[string][]string
}

func (h *handler) loadState() error {
	h.handled = map[string][]string{}
	data, err := os.ReadFile(h.statePath)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	return json.Unmarshal(data, &h.handled)
}

func (h *handler) saveState() error {
	data, err := json.MarshalIndent(h.handled, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(h.statePath), 0o755); err != nil {
		return err
	}
	return os.WriteFile(h.statePath, data, 0o644)
}

func (h *handler) isHandled(key, id string) bool {
	for _, handled := range h.handled[key] {
		if handled == id {
			return true
		}
	}
	return false
}

// pending is what one topic's agent run has to address: comments from across
// every change sharing that topic, since they're all one conversation.
type pending struct {
	project  string
	topic    string
	changes  []gerrit.Change
	comments map[int][]gerrit.Comment
	newest   time.Time
}

// sweep acts on every topic that's ready, and returns how long to wait before
// the earliest held one becomes ready.
func (h *handler) sweep(ctx context.Context) (time.Duration, error) {
	changes, err := h.client.Query("status:open", "owner:"+pusher)
	if err != nil {
		return 0, err
	}

	topics := map[string]*pending{}
	for _, change := range changes {
		if change.Topic == "" {
			// Nothing ties it to a session, so there's no conversation to
			// continue; leave it for a human.
			continue
		}
		key := change.Project + "~" + change.Topic
		if topics[key] == nil {
			topics[key] = &pending{
				project:  change.Project,
				topic:    change.Topic,
				comments: map[int][]gerrit.Comment{},
			}
		}
		topics[key].changes = append(topics[key].changes, change)
	}

	var soonest time.Duration
	for _, topic := range topics {
		if err := ctx.Err(); err != nil {
			return 0, err
		}
		if err := h.collect(topic); err != nil {
			log.Printf("%s topic %s: %v", topic.project, topic.topic, err)
			continue
		}
		if len(topic.comments) == 0 {
			continue
		}

		if age := time.Since(topic.newest); age < *debounce {
			wait := *debounce - age
			log.Printf("%s topic %s: holding for %s in case there's more review coming",
				topic.project, topic.topic, wait.Round(time.Second))
			if soonest == 0 || wait < soonest {
				soonest = wait
			}
			continue
		}

		if err := h.act(ctx, topic); err != nil {
			log.Printf("%s topic %s: %v", topic.project, topic.topic, err)
		}
	}
	return soonest, nil
}

// collect gathers the reviewer's unhandled comments for a topic. A change seen
// for the first time has its existing comments marked handled rather than
// replayed, so adopting work in progress doesn't dump its history on the agent.
func (h *handler) collect(topic *pending) error {
	for _, change := range topic.changes {
		key := fmt.Sprintf("%s~%d", change.Project, change.Number)
		_, seen := h.handled[key]

		comments, err := h.client.Comments(change.Number)
		if err != nil {
			return err
		}

		var fresh []gerrit.Comment
		for _, comment := range comments {
			if comment.Author.Username != reviewer || h.isHandled(key, comment.ID) {
				continue
			}
			fresh = append(fresh, comment)
		}

		if !seen {
			h.handled[key] = []string{}
			for _, comment := range fresh {
				h.handled[key] = append(h.handled[key], comment.ID)
			}
			if err := h.saveState(); err != nil {
				return err
			}
			continue
		}

		for _, comment := range fresh {
			updated, err := gerrit.ParseTime(comment.Updated)
			if err == nil && updated.After(topic.newest) {
				topic.newest = updated
			}
		}
		if len(fresh) > 0 {
			topic.comments[change.Number] = fresh
		}
	}
	return nil
}

func (h *handler) act(ctx context.Context, topic *pending) error {
	if tmuxSessionExists(session.TmuxName(topic.project, topic.topic)) {
		// Deliberately not marking anything handled: the comments are deferred,
		// not dropped, and the next sweep takes them once the session is gone.
		log.Printf("%s topic %s: live session attached, deferring", topic.project, topic.topic)
		return nil
	}

	count := 0
	for _, comments := range topic.comments {
		count += len(comments)
	}
	log.Printf("%s topic %s: acting on %d comment(s) across %d change(s)",
		topic.project, topic.topic, count, len(topic.comments))

	reply, runErr := h.runAgent(ctx, topic)

	// Whatever happened, say so on the changes that prompted it: silence there
	// looks identical to the handler being broken.
	for _, change := range topic.changes {
		if len(topic.comments[change.Number]) == 0 {
			continue
		}
		review := gerrit.ReviewInput{
			Message: reply,
			// Nothing Gerrit does on its own puts the reviewer back in the
			// attention set - not a reply, not a new patch set - so a change
			// would leave "Your Turn" and never return.
			AddToAttentionSet: []gerrit.AttentionSetInput{
				{User: reviewer, Reason: "agent responded to review comments"},
			},
		}
		if err := h.client.Review(change.Number, change.CurrentPatchSet.Number, review); err != nil {
			return fmt.Errorf("replying on change %d: %w (agent run: %v)", change.Number, err, runErr)
		}
		key := fmt.Sprintf("%s~%d", change.Project, change.Number)
		for _, comment := range topic.comments[change.Number] {
			h.handled[key] = append(h.handled[key], comment.ID)
		}
		sort.Strings(h.handled[key])
	}
	if err := h.saveState(); err != nil {
		return fmt.Errorf("saving state: %w", err)
	}
	return runErr
}

func (h *handler) runAgent(ctx context.Context, topic *pending) (string, error) {
	workspace := session.Workspace(h.home, topic.project, topic.topic)
	if _, err := os.Stat(workspace); err != nil {
		return "", fmt.Errorf("no workspace at %s; this change was proposed from somewhere else", workspace)
	}

	id := session.ID(topic.project, topic.topic)
	started := session.Started(h.home, topic.project, topic.topic)
	args := []string{"-p", "--permission-mode", "bypassPermissions", "--output-format", "json"}
	if started {
		args = append(args, "--resume", id)
	} else {
		args = append(args, "--session-id", id)
	}
	args = append(args, prompt(topic, started))

	ctx, cancel := context.WithTimeout(ctx, *runLimit)
	defer cancel()

	cmd := exec.CommandContext(ctx, "claude", args...)
	cmd.Dir = workspace
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	footer := fmt.Sprintf("\n\n---\nSession %s. To take over: `slop %s %s` in the agent VM.",
		id, topic.topic, topic.project)
	if err := cmd.Run(); err != nil {
		detail := strings.TrimSpace(stderr.String())
		if detail == "" {
			detail = strings.TrimSpace(stdout.String())
		}
		return fmt.Sprintf("The agent run failed, so this hasn't been addressed.\n\n%s%s",
			truncate(detail, 2000), footer), fmt.Errorf("claude: %w", err)
	}

	var result struct {
		Result  string `json:"result"`
		IsError bool   `json:"is_error"`
	}
	if err := json.Unmarshal([]byte(stdout.String()), &result); err != nil {
		return "The agent produced output this handler couldn't read." + footer,
			fmt.Errorf("decoding claude output: %w", err)
	}
	if result.IsError {
		return fmt.Sprintf("The agent reported an error:\n\n%s%s", truncate(result.Result, 2000), footer),
			errors.New("claude reported an error")
	}
	return truncate(result.Result, 60000) + footer, nil
}

func prompt(topic *pending, resuming bool) string {
	var b strings.Builder
	if resuming {
		fmt.Fprintf(&b, "New review feedback on your change, topic %q:\n\n", topic.topic)
	} else {
		// No transcript: the session that made this change is gone, so the
		// change itself has to stand in for everything it knew.
		fmt.Fprintf(&b, "You are picking up topic %q in a checkout at the current directory, "+
			"without the conversation that produced it. Read the change with "+
			"`git log origin/master..HEAD` and `git diff origin/master` before acting.\n\n"+
			"Review feedback to address:\n\n", topic.topic)
	}

	for _, change := range topic.changes {
		comments := topic.comments[change.Number]
		if len(comments) == 0 {
			continue
		}
		fmt.Fprintf(&b, "On change %d (%q):\n", change.Number, change.Subject)
		for _, comment := range comments {
			where := comment.File
			if comment.Line > 0 {
				where = fmt.Sprintf("%s:%d", comment.File, comment.Line)
			}
			if where == "/PATCHSET_LEVEL" || where == "" {
				fmt.Fprintf(&b, "  %s\n", comment.Message)
			} else {
				fmt.Fprintf(&b, "  %s: %s\n", where, comment.Message)
			}
		}
		b.WriteString("\n")
	}

	b.WriteString("Address the feedback in this working tree and commit - amending the commit " +
		"the comment is about, rather than adding a fixup, since each commit is a separate " +
		"change under review. If the feedback is a question rather than a request, answer it " +
		"instead of changing code. When you have committed something, run `slop-pr` to publish " +
		"a new patch set. Your reply to this message is posted as a review comment, so write it " +
		"for the reviewer: say what you changed, or answer the question, and flag anything you " +
		"disagreed with.")
	return b.String()
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max] + "\n[truncated]"
}

func tmuxSessionExists(name string) bool {
	return exec.Command("tmux", "has-session", "-t", "="+name).Run() == nil
}

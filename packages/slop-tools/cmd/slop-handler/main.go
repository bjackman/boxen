// slop-handler drives an agent from pull request review comments, so that
// reviewing a change needs nothing but the forge. See design_docs/agent_prs.md.
//
// A Forgejo webhook only wakes it up; the work is always to reconcile against
// the API. That way a missed delivery, a restart, or a comment deferred
// because a human was attached all recover on the next sweep, and there's one
// code path rather than two.
package main

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"

	"github.com/bjackman/boxen/slop-tools/internal/forgejo"
	"github.com/bjackman/boxen/slop-tools/internal/session"
)

// Set at build time.
var (
	forgejoURL   = "https://forgejo.home.yawn.io"
	owner        = "brendan"
	pusher       = "slopbot"
	reviewer     = "brendan"
	passwordFile = "/run/agenix/slopbot-forgejo-password"
	secretFile   = "/run/agenix/slopbot-webhook-secret"
	agentLabel   = "agent"
	// Comma-separated, matching bjackman.forgejoAgentRepos.
	repos = "boxen"
)

var (
	listen    = flag.String("listen", ":9100", "address to serve the webhook on")
	stateDir  = flag.String("state-dir", "/var/lib/slop-handler", "where to record which comments have been handled")
	sweepFreq = flag.Duration("sweep", 5*time.Minute, "how often to reconcile against the API regardless of webhooks")
	runLimit  = flag.Duration("run-limit", 30*time.Minute, "how long a single agent run may take")
	once      = flag.Bool("once", false, "sweep once and exit, rather than serving")
)

func main() {
	flag.Parse()
	log.SetFlags(0)
	if err := run(); err != nil {
		log.Fatalf("slop-handler: %v", err)
	}
}

func run() error {
	client, err := forgejo.NewClient(forgejoURL, pusher, passwordFile)
	if err != nil {
		return err
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	handler := &handler{client: client, home: home, statePath: filepath.Join(*stateDir, "handled.json")}
	if err := handler.loadState(); err != nil {
		return err
	}

	if *once {
		return handler.sweep(context.Background())
	}

	secret, err := os.ReadFile(secretFile)
	if err != nil {
		return fmt.Errorf("reading webhook secret: %w", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// Buffered so a burst of deliveries collapses into one pending sweep: a
	// review with five inline comments should be one agent run, not five.
	wake := make(chan struct{}, 1)
	go serve(ctx, strings.TrimSpace(string(secret)), wake)

	ticker := time.NewTicker(*sweepFreq)
	defer ticker.Stop()

	for {
		if err := handler.sweep(ctx); err != nil {
			if ctx.Err() != nil {
				return nil
			}
			log.Printf("sweep failed: %v", err)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-wake:
		case <-ticker.C:
		}
	}
}

func serve(ctx context.Context, secret string, wake chan<- struct{}) {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /forgejo", func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
		if err != nil {
			http.Error(w, "read failed", http.StatusBadRequest)
			return
		}
		// The payload is only a hint that something changed; the sweep reads
		// the truth from the API. But it still has to be authentic, or anyone
		// who can reach this port can spend my tokens.
		if !validSignature(secret, body, r.Header.Get("X-Forgejo-Signature"), r.Header.Get("X-Gitea-Signature")) {
			log.Printf("rejected webhook delivery with a bad signature")
			http.Error(w, "bad signature", http.StatusForbidden)
			return
		}
		log.Printf("webhook delivery accepted, sweeping")
		select {
		case wake <- struct{}{}:
		default:
		}
		w.WriteHeader(http.StatusNoContent)
	})

	server := &http.Server{Addr: *listen, Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	go func() {
		<-ctx.Done()
		server.Close()
	}()
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Printf("webhook listener stopped: %v", err)
	}
}

func validSignature(secret string, body []byte, signatures ...string) bool {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	want := hex.EncodeToString(mac.Sum(nil))
	for _, got := range signatures {
		if got != "" && hmac.Equal([]byte(got), []byte(want)) {
			return true
		}
	}
	return false
}

type handler struct {
	client    *forgejo.Client
	home      string
	statePath string
	handled   map[string][]int64
}

func (h *handler) loadState() error {
	h.handled = map[string][]int64{}
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

func (h *handler) isHandled(key string, id int64) bool {
	for _, handled := range h.handled[key] {
		if handled == id {
			return true
		}
	}
	return false
}

// sweep looks at every agent pull request and acts on anything the reviewer
// has said since the last run.
func (h *handler) sweep(ctx context.Context) error {
	for _, repo := range strings.Split(repos, ",") {
		repo = strings.TrimSpace(repo)
		if repo == "" {
			continue
		}
		pulls, err := h.client.PullsWithLabel(owner, repo, agentLabel)
		if err != nil {
			return err
		}
		for _, pr := range pulls {
			if err := ctx.Err(); err != nil {
				return err
			}
			if err := h.handlePull(ctx, repo, pr); err != nil {
				log.Printf("%s pull request #%d: %v", repo, pr.Number, err)
			}
		}
	}
	return nil
}

type trigger struct {
	id   int64
	text string
}

func (h *handler) handlePull(ctx context.Context, repo string, pr forgejo.PullRequest) error {
	key := fmt.Sprintf("%s#%d", repo, pr.Number)
	triggers, err := h.pendingTriggers(key, repo, pr)
	if err != nil {
		return err
	}
	if len(triggers) == 0 {
		return nil
	}

	topic := pr.Topic()
	if tmuxSessionExists(session.TmuxName(repo, topic)) {
		// Deliberately not marking these handled: the comment is deferred, not
		// dropped, and the next sweep picks it up once the session is gone.
		log.Printf("%s: live session attached, deferring %d comment(s)", key, len(triggers))
		return nil
	}

	log.Printf("%s: acting on %d comment(s)", key, len(triggers))
	reply, runErr := h.runAgent(ctx, repo, topic, pr, triggers)

	// Whatever happened, say so on the pull request: silence there looks
	// identical to the handler being broken.
	if postErr := h.client.PostComment(owner, repo, pr.Number, reply); postErr != nil {
		return fmt.Errorf("posting reply: %w (agent run: %v)", postErr, runErr)
	}

	for _, t := range triggers {
		h.handled[key] = append(h.handled[key], t.id)
	}
	sort.Slice(h.handled[key], func(i, j int) bool { return h.handled[key][i] < h.handled[key][j] })
	if err := h.saveState(); err != nil {
		return fmt.Errorf("saving state: %w", err)
	}
	return runErr
}

// pendingTriggers is everything the reviewer has said on this pull request that
// hasn't been acted on. On the first sighting of a pull request nothing is
// pending: the change was just proposed, and the description already said it.
func (h *handler) pendingTriggers(key, repo string, pr forgejo.PullRequest) ([]trigger, error) {
	_, seen := h.handled[key]

	comments, err := h.client.IssueComments(owner, repo, pr.Number)
	if err != nil {
		return nil, err
	}
	var triggers []trigger
	for _, comment := range comments {
		if comment.User.Login == reviewer && !h.isHandled(key, comment.ID) {
			triggers = append(triggers, trigger{id: comment.ID, text: comment.Body})
		}
	}

	reviews, err := h.client.Reviews(owner, repo, pr.Number)
	if err != nil {
		return nil, err
	}
	for _, review := range reviews {
		if review.User.Login != reviewer {
			continue
		}
		if review.Body != "" && !h.isHandled(key, review.ID) {
			triggers = append(triggers, trigger{id: review.ID, text: review.Body})
		}
		reviewComments, err := h.client.ReviewComments(owner, repo, pr.Number, review.ID)
		if err != nil {
			return nil, err
		}
		for _, comment := range reviewComments {
			if h.isHandled(key, comment.ID) {
				continue
			}
			where := comment.Path
			if comment.Line > 0 {
				where = fmt.Sprintf("%s:%d", comment.Path, comment.Line)
			}
			triggers = append(triggers, trigger{
				id:   comment.ID,
				text: fmt.Sprintf("On %s:\n%s", where, comment.Body),
			})
		}
	}

	if !seen {
		// Record them as handled so that adopting an existing pull request
		// doesn't replay its whole history at the agent.
		h.handled[key] = []int64{}
		for _, t := range triggers {
			h.handled[key] = append(h.handled[key], t.id)
		}
		return nil, h.saveState()
	}
	return triggers, nil
}

func (h *handler) runAgent(ctx context.Context, repo, topic string, pr forgejo.PullRequest, triggers []trigger) (string, error) {
	workspace := session.Workspace(h.home, repo, topic)
	if _, err := os.Stat(workspace); err != nil {
		return "", fmt.Errorf("no workspace at %s; this change was proposed from somewhere else", workspace)
	}

	id := session.ID(repo, topic)
	args := []string{"-p", "--permission-mode", "bypassPermissions", "--output-format", "json"}
	if session.Started(h.home, repo, topic) {
		args = append(args, "--resume", id)
	} else {
		args = append(args, "--session-id", id)
	}
	args = append(args, prompt(pr, triggers, session.Started(h.home, repo, topic)))

	ctx, cancel := context.WithTimeout(ctx, *runLimit)
	defer cancel()

	cmd := exec.CommandContext(ctx, "claude", args...)
	cmd.Dir = workspace
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	footer := fmt.Sprintf("\n\n---\n*Session `%s`. To take over: `slop %s %s` in the agent VM.*", id, topic, repo)
	if err := cmd.Run(); err != nil {
		detail := strings.TrimSpace(stderr.String())
		if detail == "" {
			detail = strings.TrimSpace(stdout.String())
		}
		return fmt.Sprintf("The agent run failed, so this comment hasn't been addressed.\n\n```\n%s\n```%s", truncate(detail, 2000), footer),
			fmt.Errorf("claude: %w", err)
	}

	var result struct {
		Result  string `json:"result"`
		IsError bool   `json:"is_error"`
	}
	if err := json.Unmarshal([]byte(stdout.String()), &result); err != nil {
		return "The agent produced output this handler couldn't read." + footer, fmt.Errorf("decoding claude output: %w", err)
	}
	if result.IsError {
		return fmt.Sprintf("The agent reported an error:\n\n%s%s", truncate(result.Result, 2000), footer), errors.New("claude reported an error")
	}
	return truncate(result.Result, 60000) + footer, nil
}

func prompt(pr forgejo.PullRequest, triggers []trigger, resuming bool) string {
	var b strings.Builder
	if resuming {
		fmt.Fprintf(&b, "New review feedback on your pull request #%d (%q):\n\n", pr.Number, pr.Title)
	} else {
		// No transcript: the session that made this change is gone, so the
		// pull request has to stand in for everything it knew.
		fmt.Fprintf(&b, "You are picking up pull request #%d (%q) in a checkout at the current "+
			"directory, without the conversation that produced it. Read the change with "+
			"`git log origin/master..HEAD` and `git diff origin/master` before acting.\n\n"+
			"Review feedback to address:\n\n", pr.Number, pr.Title)
	}
	for _, t := range triggers {
		fmt.Fprintf(&b, "%s\n\n", t.text)
	}
	b.WriteString("Address the feedback in this working tree and commit. If the feedback is a " +
		"question rather than a request, answer it instead of changing code. When you have " +
		"committed something, run `slop-pr` to publish a new version. Your reply to this " +
		"message is posted as a comment on the pull request, so write it for the reviewer: " +
		"say what you changed, or answer the question, and flag anything you disagreed with.")
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

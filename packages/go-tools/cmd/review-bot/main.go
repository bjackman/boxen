// review-bot reviews changes it has been added to as a reviewer, with a fresh
// headless Claude Code that can read the checkout and nothing else, and posts
// the findings as inline comments with a Code-Review vote. See
// design_docs/review_bot.md.
//
// Like gerrit-ci it keeps no state that matters on disk: a patch set without
// its vote is one to review, and the rounds a change has had are counted from
// its own messages.
package main

import (
	"bytes"
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
	"slices"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/bjackman/boxen/go-tools/gerrit"
	"github.com/bjackman/boxen/go-tools/internal/review"
)

var (
	gerritHost  = flag.String("gerrit-host", "pizza", "Gerrit host to talk to")
	gerritPort  = flag.String("gerrit-port", "29418", "Gerrit SSH port")
	user        = flag.String("user", "review-bot", "Gerrit account to review as")
	keyFilePath = flag.String("key-file", "/run/agenix/review-bot-ssh-privkey",
		"Path to the SSH private key")
	project      = flag.String("project", "boxen", "The one project whose changes are reviewed")
	stateDirPath = flag.String("state-dir", "/var/lib/review-bot",
		"Path to the directory holding the checkout and each review's inputs")
	maxRounds = flag.Int("max-rounds", 5,
		"how many rounds a change gets before it's left to a human")
	maxAttempts = flag.Int("max-attempts", 3,
		"how many failed attempts at reviewing a patch set before giving up on it until restarted")
	model     = flag.String("model", "", "Model to review with; empty for Claude Code's default")
	sweepFreq = flag.Duration("sweep", 5*time.Minute,
		"how often to reconcile against the API regardless of events")
	runLimit = flag.Duration("run-limit", 20*time.Minute, "how long a single review may take")
	once     = flag.Bool("once", false, "review what's pending and exit, rather than watching")
)

func main() {
	flag.Parse()
	log.SetFlags(0)
	if err := run(); err != nil {
		log.Fatalf("review-bot: %v", err)
	}
}

func run() error {
	port, err := strconv.Atoi(*gerritPort)
	if err != nil {
		return fmt.Errorf("parsing --gerrit-port %q: %w", *gerritPort, err)
	}
	client, err := gerrit.NewClient(gerrit.Config{
		Host: *gerritHost, Port: port, User: *user, KeyFile: *keyFilePath,
	})
	if err != nil {
		return fmt.Errorf("creating Gerrit client for %s:%d: %w", *gerritHost, port, err)
	}
	r := &reviewer{
		client:     client,
		repoPath:   filepath.Join(*stateDirPath, "repo"),
		inputsPath: filepath.Join(*stateDirPath, "inputs"),
		failures:   map[string]int{},
	}

	if *once {
		return r.sweep(context.Background())
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// Buffered so a burst of events collapses into one pending sweep.
	wake := make(chan struct{}, 1)
	go client.Watch(ctx, func(event gerrit.Event) bool {
		if event.Change.Project != *project {
			return false
		}
		switch {
		case event.Type == gerrit.EventReviewerAdded && event.Reviewer.Username == *user:
			log.Printf("added to change %d, sweeping", event.Change.Number)
		case event.Type == gerrit.EventPatchSetCreated:
			log.Printf("new patch set on change %d, sweeping", event.Change.Number)
		default:
			return false
		}
		return true
	}, wake)

	ticker := time.NewTicker(*sweepFreq)
	defer ticker.Stop()

	for {
		if err := r.sweep(ctx); err != nil {
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

type reviewer struct {
	client   *gerrit.Client
	repoPath string
	// Path to the directory a review's inputs are written to, beside the
	// checkout rather than in it so that they're never mistaken for part of
	// the change.
	inputsPath string
	// Failed attempts per patch set, by name. In memory only: a restart is
	// the way to try again after giving up.
	failures map[string]int
}

func patchSetName(change int, patchSet int) string {
	return fmt.Sprintf("%d-%d", change, patchSet)
}

func (r *reviewer) sweep(ctx context.Context) error {
	changes, err := r.client.QueryWithComments("status:open", "project:"+*project, "reviewer:"+*user)
	if err != nil {
		return fmt.Errorf("querying open changes on %s with %s as reviewer: %w", *project, *user, err)
	}
	for _, change := range pending(changes, *user, *maxRounds) {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		name := patchSetName(change.Number, change.CurrentPatchSet.Number)
		if r.failures[name] >= *maxAttempts {
			continue
		}
		if err := r.review(ctx, change); err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			// One bad change mustn't stop the others being reviewed.
			log.Printf("reviewing change %d: %v", change.Number, err)
			r.failures[name]++
			r.report(change, r.failures[name], err)
		}
	}
	return nil
}

// pending returns the changes whose current patch set has no vote from user
// and that haven't had all their rounds, oldest first: a series is usually
// numbered from the bottom, and reviewing it in that order reads best.
func pending(changes []gerrit.Change, user string, maxRounds int) []gerrit.Change {
	var out []gerrit.Change
	for _, change := range changes {
		if change.CurrentPatchSet.Voted(review.Label, user) {
			continue
		}
		if done, _ := review.Rounds(change.Messages, user); done >= maxRounds {
			continue
		}
		out = append(out, change)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Number < out[j].Number })
	return out
}

// report says on the change that a review failed, the first time and when
// giving up. A review that never arrives looks the same as one that's slow.
func (r *reviewer) report(change gerrit.Change, attempt int, reviewErr error) {
	var msg string
	switch attempt {
	case 1:
		msg = fmt.Sprintf("The review bot couldn't review this patch set, and will retry: %v", reviewErr)
	case *maxAttempts:
		msg = fmt.Sprintf("The review bot has failed to review this patch set %d times and has given up "+
			"on it until it's restarted or there's a new patch set: %v", attempt, reviewErr)
	default:
		return
	}
	if err := r.client.Review(change.Number, change.CurrentPatchSet.Number, gerrit.ReviewInput{Message: msg}); err != nil {
		log.Printf("reporting the failure to review change %d: %v", change.Number, err)
	}
}

func (r *reviewer) review(ctx context.Context, change gerrit.Change) error {
	patchSet := change.CurrentPatchSet
	log.Printf("reviewing change %d patch set %d", change.Number, patchSet.Number)
	round, _ := review.Rounds(change.Messages, *user)
	round++

	if err := r.fetch(ctx, patchSet.Ref, change.Branch); err != nil {
		return fmt.Errorf("fetching %s into %s: %w", patchSet.Ref, r.repoPath, err)
	}
	in, err := r.prepareInputs(ctx)
	if err != nil {
		return fmt.Errorf("preparing the inputs to reviewing %s: %w", patchSet.Ref, err)
	}

	prompt := buildPrompt(change, round, *maxRounds, in)
	runCtx, cancel := context.WithTimeout(ctx, *runLimit)
	defer cancel()
	result, err := runClaude(runCtx, r.repoPath, r.inputsPath, prompt)
	if err != nil {
		return fmt.Errorf("running the reviewer: %w", err)
	}

	comments := place(result.Findings, in.files, r.repoPath)
	vote := 1
	if len(result.Findings) > 0 {
		vote = -1
	}
	msg := review.RoundMessage(round, *maxRounds) + " " + result.Summary
	if err := r.client.Review(change.Number, patchSet.Number, gerrit.ReviewInput{
		Message:  msg,
		Labels:   map[string]int{review.Label: vote},
		Comments: comments,
	}); err != nil {
		return fmt.Errorf("posting %d findings and %s%+d on %d,%d: %w",
			len(result.Findings), review.Label, vote, change.Number, patchSet.Number, err)
	}
	return nil
}

func (r *reviewer) fetch(ctx context.Context, ref, branch string) error {
	if _, err := os.Stat(filepath.Join(r.repoPath, ".git")); errors.Is(err, os.ErrNotExist) {
		url := fmt.Sprintf("ssh://%s@%s:%s/%s", *user, *gerritHost, *gerritPort, *project)
		if _, err := git(ctx, "", "clone", url, r.repoPath); err != nil {
			return fmt.Errorf("cloning %s: %w", url, err)
		}
	}
	if _, err := git(ctx, r.repoPath, "fetch", "origin",
		"+"+ref+":refs/review/change", "+refs/heads/"+branch+":refs/review/base"); err != nil {
		return fmt.Errorf("fetching %s and %s: %w", ref, branch, err)
	}
	if _, err := git(ctx, r.repoPath, "checkout", "--force", "--detach", "refs/review/change"); err != nil {
		return fmt.Errorf("checking out %s: %w", ref, err)
	}
	if _, err := git(ctx, r.repoPath, "clean", "-xfd"); err != nil {
		return fmt.Errorf("cleaning the tree after checking out %s: %w", ref, err)
	}
	return nil
}

type inputs struct {
	// The change's commit message and diff, which go in the prompt.
	patch string
	// Path to the earlier commits of the series, or empty if there are none.
	seriesPath string
	// The files the change leaves in the tree, which are the ones a finding
	// can be placed on.
	files []string
}

func (r *reviewer) prepareInputs(ctx context.Context) (inputs, error) {
	var in inputs
	if err := os.RemoveAll(r.inputsPath); err != nil {
		return in, fmt.Errorf("clearing %s: %w", r.inputsPath, err)
	}
	if err := os.MkdirAll(r.inputsPath, 0o755); err != nil {
		return in, fmt.Errorf("creating %s: %w", r.inputsPath, err)
	}

	patch, err := git(ctx, r.repoPath, "show", "--format=fuller", "refs/review/change")
	if err != nil {
		return in, fmt.Errorf("reading the change: %w", err)
	}
	in.patch = patch

	series, err := git(ctx, r.repoPath, "log", "--reverse", "--patch", "--format=fuller",
		"refs/review/base..refs/review/change~")
	if err != nil {
		return in, fmt.Errorf("reading the rest of the series: %w", err)
	}
	if strings.TrimSpace(series) != "" {
		in.seriesPath = filepath.Join(r.inputsPath, "series.patch")
		if err := os.WriteFile(in.seriesPath, []byte(series), 0o644); err != nil {
			return in, fmt.Errorf("writing %s: %w", in.seriesPath, err)
		}
	}

	files, err := git(ctx, r.repoPath, "diff", "--name-only", "--diff-filter=d",
		"refs/review/change~", "refs/review/change")
	if err != nil {
		return in, fmt.Errorf("listing the files the change touches: %w", err)
	}
	in.files = strings.Fields(files)
	return in, nil
}

func buildPrompt(change gerrit.Change, round, maxRounds int, in inputs) string {
	var b strings.Builder
	fmt.Fprintf(&b, "You are reviewing change %d, %q, in %s, a repository of NixOS and Home Manager "+
		"configurations for a small homelab. The change was written by another Claude Code agent: "+
		"your findings go back to it, and it will fix them or argue. The repository's owner reads "+
		"the whole exchange afterwards.\n\n", change.Number, change.Subject, change.Project)
	b.WriteString("The working directory is a checkout of the change. Read CLAUDE.md at its root " +
		"before anything else: it sets the repository's conventions, including strict rules about " +
		"code comments, and breaking them is worth a finding.\n\n")
	fmt.Fprintf(&b, "This is the change:\n\n%s\n\n", in.patch)
	if in.seriesPath != "" {
		fmt.Fprintf(&b, "It's part of a series. The commits below it, which it builds on, are in %s. "+
			"Review only this change: a problem in those belongs on the change that introduces it.\n\n",
			in.seriesPath)
	}
	b.WriteString("Look for bugs, things that won't build or evaluate, behaviour that doesn't " +
		"match the commit message, design problems, and breaches of CLAUDE.md. Read the code " +
		"to confirm a suspicion before you raise it. Leave out matters of taste, and don't pad: " +
		"no findings is the right answer for a good change.\n\n")
	b.WriteString("For each finding, file is the path from the repository root of a file this " +
		"change modifies, line is a line in the new version of that file, and message says " +
		"concisely what is wrong and why. For a point about the change as a whole or its " +
		"commit message, give an empty file and line 0. The summary is a sentence or two " +
		"about the change as a whole.\n")

	if round > 1 {
		fmt.Fprintf(&b, "\nThis is round %d of %d. Below is what has been said on the change so far. "+
			"Don't raise a point again once it has been answered, unless the answer is wrong, "+
			"in which case say why.\n", round, maxRounds)
		for _, patchSet := range change.PatchSets {
			for _, comment := range patchSet.Comments {
				where := comment.File
				if comment.Line > 0 {
					where += ":" + strconv.Itoa(comment.Line)
				}
				fmt.Fprintf(&b, "\n[patch set %d, %s] %s: %s\n",
					patchSet.Number, where, comment.Reviewer.Username, comment.Message)
			}
		}
	}
	return b.String()
}

type finding struct {
	File    string `json:"file"`
	Line    int    `json:"line"`
	Message string `json:"message"`
}

type result struct {
	Summary  string    `json:"summary"`
	Findings []finding `json:"findings"`
}

const resultSchema = `{
  "type": "object",
  "properties": {
    "summary": {"type": "string"},
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "line": {"type": "integer"},
          "message": {"type": "string"}
        },
        "required": ["file", "line", "message"]
      }
    }
  },
  "required": ["summary", "findings"]
}`

// runClaude reviews in a session that can read the checkout and the inputs and
// do nothing else. --restricted also ignores settings files, and
// --strict-mcp-config MCP servers, so that nothing the change adds to the
// checkout can give the reviewer more than that.
func runClaude(ctx context.Context, repoPath, inputsPath, prompt string) (*result, error) {
	args := []string{
		"-p",
		"--restricted",
		"--tools", "Read,Grep,Glob",
		"--strict-mcp-config",
		"--no-session-persistence",
		"--add-dir", inputsPath,
		"--output-format", "json",
		"--json-schema", resultSchema,
	}
	if *model != "" {
		args = append(args, "--model", *model)
	}
	cmd := exec.CommandContext(ctx, "claude", args...)
	cmd.Dir = repoPath
	cmd.Stdin = strings.NewReader(prompt)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("claude: %w: %s", err, truncate(stderr.String()+stdout.String(), 500))
	}
	return parseOutput(stdout.Bytes())
}

func parseOutput(out []byte) (*result, error) {
	var output struct {
		IsError          bool    `json:"is_error"`
		Result           string  `json:"result"`
		StructuredOutput *result `json:"structured_output"`
	}
	if err := json.Unmarshal(out, &output); err != nil {
		return nil, fmt.Errorf("decoding claude's output: %w: %s", err, truncate(string(out), 500))
	}
	if output.IsError {
		return nil, fmt.Errorf("claude reported an error: %s", truncate(output.Result, 500))
	}
	if output.StructuredOutput == nil {
		return nil, fmt.Errorf("claude's output has no findings: %s", truncate(output.Result, 500))
	}
	return output.StructuredOutput, nil
}

// patchSetLevel is the path Gerrit takes a comment on the change as a whole at.
const patchSetLevel = "/PATCHSET_LEVEL"

// place turns findings into comments. Gerrit rejects the whole review over one
// comment on a file the change doesn't touch or a line the file doesn't have,
// so a finding that can't be placed where it says goes on the change as a
// whole instead, with where it meant.
func place(findings []finding, files []string, repoPath string) map[string][]gerrit.CommentInput {
	comments := map[string][]gerrit.CommentInput{}
	for _, f := range findings {
		comment := gerrit.CommentInput{Message: f.Message, Unresolved: true}
		path := patchSetLevel
		if slices.Contains(files, f.File) && f.Line >= 0 && f.Line <= lineCount(filepath.Join(repoPath, f.File)) {
			path = f.File
			comment.Line = f.Line
		} else if f.File != "" {
			where := f.File
			if f.Line > 0 {
				where += ":" + strconv.Itoa(f.Line)
			}
			comment.Message = where + ": " + f.Message
		}
		comments[path] = append(comments[path], comment)
	}
	return comments
}

// lineCount is -1 for a file that can't be read, which no line is within.
func lineCount(path string) int {
	contents, err := os.ReadFile(path)
	if err != nil {
		return -1
	}
	n := bytes.Count(contents, []byte("\n"))
	if len(contents) > 0 && !bytes.HasSuffix(contents, []byte("\n")) {
		n++
	}
	return n
}

func git(ctx context.Context, dir string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, "git", args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), fmt.Sprintf(
		"GIT_SSH_COMMAND=ssh -i '%s' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new", *keyFilePath))
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("git %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return stdout.String(), nil
}

func truncate(s string, max int) string {
	s = strings.TrimSpace(s)
	if len(s) <= max {
		return s
	}
	return s[:max] + "..."
}

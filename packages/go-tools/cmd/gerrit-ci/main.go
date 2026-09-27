// gerrit-ci builds every patch set of a project and votes Verified on it, so
// that a change can't be submitted without its checks having passed. See
// design_docs/gerrit_ci.md.
//
// The event stream only wakes it up: the work is always to reconcile against
// the API, so a dropped stream or a restart costs latency rather than
// correctness. There is no state on disk to get out of step with Gerrit -
// "have I done this one" is the vote itself.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
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

	"github.com/bjackman/boxen/go-tools/gerrit"
)

var (
	gerritHost  = flag.String("gerrit-host", "pizza", "Gerrit host to talk to")
	gerritPort  = flag.String("gerrit-port", "29418", "Gerrit SSH port")
	user        = flag.String("user", "ci-bot", "Gerrit account to vote as")
	keyFilePath = flag.String("key-file", "/run/agenix/ci-bot-ssh-privkey",
		"Path to the SSH private key")
	project   = flag.String("project", "boxen", "The one project whose patch sets are checked")
	label     = flag.String("label", "Verified", "Label to vote")
	nixSystem = flag.String("nix-system", "x86_64-linux", "Nix system whose checks are built")
	logURL    = flag.String("log-url", "https://gerrit-ci-logs.home.yawn.io",
		"Base URL the build logs are served from; the review message is useless without it")
	stateDirPath = flag.String("state-dir", "/var/lib/gerrit-ci",
		"Path to the directory holding the checkout, and logs/ which is served over HTTP")
	sweepFreq = flag.Duration("sweep", 5*time.Minute,
		"how often to reconcile against the API regardless of events")
	runLimit  = flag.Duration("run-limit", 60*time.Minute, "how long a single check may take")
	logMaxAge = flag.Duration("log-max-age", 14*24*time.Hour,
		"how long a build log is kept, which wants to outlast any open change")
	once = flag.Bool("once", false, "check what's pending and exit, rather than watching")
)

func main() {
	flag.Parse()
	log.SetFlags(0)
	if err := run(); err != nil {
		log.Fatalf("gerrit-ci: %v", err)
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
	c := &checker{
		client:       client,
		repoPath:     filepath.Join(*stateDirPath, "repo"),
		logsPath:     filepath.Join(*stateDirPath, "logs"),
		inFlightPath: filepath.Join(*stateDirPath, "in-flight"),
		reported:     map[string]bool{},
	}
	if err := os.MkdirAll(c.logsPath, 0o755); err != nil {
		return fmt.Errorf("creating log directory %s: %w", c.logsPath, err)
	}
	if err := c.failInFlight(); err != nil {
		return err
	}

	if *once {
		return c.sweep(context.Background())
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// Buffered so a burst of events collapses into one pending sweep.
	wake := make(chan struct{}, 1)
	go client.Watch(ctx, func(event gerrit.Event) bool {
		if event.Type != gerrit.EventPatchSetCreated || event.Change.Project != *project {
			return false
		}
		log.Printf("new patch set on change %d, sweeping", event.Change.Number)
		return true
	}, wake)

	ticker := time.NewTicker(*sweepFreq)
	defer ticker.Stop()

	for {
		if err := c.sweep(ctx); err != nil {
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

type checker struct {
	client   *gerrit.Client
	repoPath string
	logsPath string
	// Path to a file naming the patch set being checked, which exists only
	// while one is. The OnFailure unit reads it to report on the right change
	// when a check takes this process down with it.
	inFlightPath string
	// Patch sets that couldn't be checked and have been told so, keyed by
	// name, so that a sweep retrying them doesn't say it again every time.
	reported map[string]bool
}

func patchSetName(change int, patchSet int) string {
	return fmt.Sprintf("%d-%d", change, patchSet)
}

func (c *checker) logURL(name string) string {
	return fmt.Sprintf("%s/%s.txt", strings.TrimSuffix(*logURL, "/"), name)
}

// failInFlight votes against a patch set whose check was still running when
// this process last died. Retrying it would only kill the runner again, and
// while it's the newest change nothing older would ever be checked.
func (c *checker) failInFlight() error {
	contents, err := os.ReadFile(c.inFlightPath)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("reading %s: %w", c.inFlightPath, err)
	}
	name := strings.TrimSpace(string(contents))
	number, patchSet, err := parsePatchSetName(name)
	if err != nil {
		return fmt.Errorf("parsing %s: %w", c.inFlightPath, err)
	}
	changes, err := c.client.Query("status:open", "change:"+strconv.Itoa(number))
	if err != nil {
		return fmt.Errorf("looking up change %d, which was in flight: %w", number, err)
	}
	if len(changes) == 1 && changes[0].CurrentPatchSet.Number == patchSet {
		log.Printf("%s was in flight when the runner died; failing it", name)
		msg := fmt.Sprintf("The CI runner died while checking this patch set, so it's marked failed "+
			"rather than retried. Upload a new patch set to check it again.\n\nLog up to that point: %s",
			c.logURL(name))
		if err := c.client.Review(number, patchSet, gerrit.ReviewInput{
			Labels:  map[string]int{*label: -1},
			Message: msg,
		}); err != nil {
			return fmt.Errorf("voting %s-1 on %s, which was in flight: %w", *label, name, err)
		}
	}
	if err := os.Remove(c.inFlightPath); err != nil {
		return fmt.Errorf("removing %s: %w", c.inFlightPath, err)
	}
	return nil
}

func parsePatchSetName(name string) (int, int, error) {
	changeStr, patchSetStr, ok := strings.Cut(name, "-")
	if !ok {
		return 0, 0, fmt.Errorf("%q is not <change>-<patch set>", name)
	}
	number, err := strconv.Atoi(changeStr)
	if err != nil {
		return 0, 0, fmt.Errorf("parsing change number in %q: %w", name, err)
	}
	patchSet, err := strconv.Atoi(patchSetStr)
	if err != nil {
		return 0, 0, fmt.Errorf("parsing patch set number in %q: %w", name, err)
	}
	return number, patchSet, nil
}

func (c *checker) sweep(ctx context.Context) error {
	changes, err := c.client.Query("status:open", "project:"+*project)
	if err != nil {
		return fmt.Errorf("querying open changes on %s: %w", *project, err)
	}
	pending := pending(changes, *label, *user)
	if len(pending) == 0 {
		return nil
	}
	log.Printf("%d patch set(s) to check", len(pending))
	for _, change := range pending {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if err := c.check(ctx, change); err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			// One bad change mustn't stop the others being checked.
			log.Printf("checking change %d: %v", change.Number, err)
			c.report(change, err)
		}
	}
	if err := c.pruneLogs(); err != nil {
		log.Printf("pruning logs: %v", err)
	}
	return nil
}

// pending returns the changes whose current patch set hasn't been voted on,
// newest first: a fresh patch set is more interesting than one that has been
// waiting, and if the queue is never drained it's the recent work that matters.
func pending(changes []gerrit.Change, label, user string) []gerrit.Change {
	var out []gerrit.Change
	for _, change := range changes {
		if !change.CurrentPatchSet.Voted(label, user) {
			out = append(out, change)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Number != out[j].Number {
			return out[i].Number > out[j].Number
		}
		return out[i].CurrentPatchSet.Number > out[j].CurrentPatchSet.Number
	})
	return out
}

// report tells a change that it can't be checked. Without it, a runner that
// can't get as far as voting looks the same as one that hasn't got round to it.
func (c *checker) report(change gerrit.Change, checkErr error) {
	name := patchSetName(change.Number, change.CurrentPatchSet.Number)
	if c.reported[name] {
		return
	}
	msg := fmt.Sprintf("The CI runner couldn't check this patch set, and will keep retrying: %v", checkErr)
	if err := c.client.Review(change.Number, change.CurrentPatchSet.Number, gerrit.ReviewInput{Message: msg}); err != nil {
		log.Printf("reporting the failure to check %s: %v", name, err)
		return
	}
	c.reported[name] = true
}

func (c *checker) check(ctx context.Context, change gerrit.Change) error {
	patchSet := change.CurrentPatchSet
	name := patchSetName(change.Number, patchSet.Number)
	log.Printf("checking change %d patch set %d", change.Number, patchSet.Number)

	// Left behind by a previous run, so either that run died - which the
	// OnFailure unit should already have reported - or a second copy of this
	// job is running against the same state directory.
	if previous, err := os.ReadFile(c.inFlightPath); err == nil {
		log.Printf("warning: %s already named %s; a previous check died or another instance is running",
			c.inFlightPath, strings.TrimSpace(string(previous)))
	}
	if err := os.WriteFile(c.inFlightPath, []byte(name+"\n"), 0o644); err != nil {
		return fmt.Errorf("writing %s: %w", c.inFlightPath, err)
	}
	defer os.Remove(c.inFlightPath)
	// Being stopped is a deploy or a shutdown, not something the patch set did,
	// so it mustn't be blamed when the stop times out and ends in SIGKILL.
	defer context.AfterFunc(ctx, func() { os.Remove(c.inFlightPath) })()

	if err := c.fetch(ctx, patchSet.Ref); err != nil {
		return fmt.Errorf("fetching %s into %s: %w", patchSet.Ref, c.repoPath, err)
	}

	logPath := filepath.Join(c.logsPath, name+".txt")
	logFile, err := os.Create(logPath)
	if err != nil {
		return fmt.Errorf("creating log file %s: %w", logPath, err)
	}
	runCtx, cancel := context.WithTimeout(ctx, *runLimit)
	defer cancel()
	runErr := c.runChecks(runCtx, logFile)
	logFile.Close()

	// A check that was cancelled says nothing about the change, so don't vote.
	if ctx.Err() != nil {
		return ctx.Err()
	}

	vote := 1
	if runErr != nil {
		vote = -1
	}
	if errors.Is(runCtx.Err(), context.DeadlineExceeded) {
		runErr = fmt.Errorf("timed out after %v, which may not be the change's fault", *runLimit)
	}
	if err := c.client.Review(change.Number, patchSet.Number, gerrit.ReviewInput{
		Labels:  map[string]int{*label: vote},
		Message: message(runErr, logPath, c.logURL(name)),
	}); err != nil {
		if open, openErr := c.isOpen(change.Number); openErr == nil && !open {
			log.Printf("not voting on %s: change %d was closed while it was being checked", name, change.Number)
			return nil
		}
		return fmt.Errorf("voting %s%+d on %d,%d: %w", *label, vote, change.Number, patchSet.Number, err)
	}
	return nil
}

func (c *checker) isOpen(number int) (bool, error) {
	changes, err := c.client.Query("status:open", "change:"+strconv.Itoa(number))
	if err != nil {
		return false, fmt.Errorf("looking up whether change %d is open: %w", number, err)
	}
	return len(changes) == 1, nil
}

// runChecks builds each of the flake's checks in its own nix process, so that
// only one configuration's evaluation is ever live. We tried nix-fast-build,
// but this box doesn't have the memory for more than one nix-eval-jobs worker,
// and with one it offered nothing over this loop.
func (c *checker) runChecks(ctx context.Context, logFile io.Writer) error {
	checksAttr := ".#checks." + *nixSystem
	list := exec.CommandContext(ctx, "nix", "eval", "--json", checksAttr, "--apply", "builtins.attrNames")
	list.Dir = c.repoPath
	list.Stderr = logFile
	out, err := list.Output()
	if err != nil {
		return fmt.Errorf("listing %s: %w", checksAttr, err)
	}
	var names []string
	if err := json.Unmarshal(out, &names); err != nil {
		return fmt.Errorf("parsing the list of %s: %w", checksAttr, err)
	}

	var failed []string
	for _, name := range names {
		fmt.Fprintf(logFile, "==> %s\n", name)
		build := exec.CommandContext(ctx, "nix", "build", "--no-link", checksAttr+"."+name)
		build.Dir = c.repoPath
		build.Stdout = logFile
		build.Stderr = logFile
		if err := build.Run(); err != nil {
			if ctx.Err() != nil {
				return fmt.Errorf("building %s: %w", name, ctx.Err())
			}
			fmt.Fprintf(logFile, "==> %s failed: %v\n", name, err)
			failed = append(failed, name)
		}
	}
	if len(failed) > 0 {
		return fmt.Errorf("%s failed", strings.Join(failed, ", "))
	}
	return nil
}

// message is what shows up on the change. It carries enough to tell whether the
// failure is about the change without leaving the page, and a link for when it
// isn't - never so much that the change screen becomes the log viewer.
func message(runErr error, logPath, url string) string {
	if runErr == nil {
		return fmt.Sprintf("Checks passed.\n\nFull log: %s", url)
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Checks failed: %v.\n\nFull log: %s\n", runErr, url)
	if tail := tail(logPath, 20); tail != "" {
		fmt.Fprintf(&b, "\n%s", tail)
	}
	return b.String()
}

// tailBytes bounds how much of a log is read to find its last lines. A failing
// evaluation can print megabytes, and only the end of it is ever quoted.
const tailBytes = 64 * 1024

// tail reads the last n lines of the file at path, for the excerpt in the
// review message. A missing or unreadable log is not worth failing the report
// over: the vote matters more than the excerpt.
func tail(path string, n int) string {
	file, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return ""
	}
	size := info.Size()
	offset := int64(0)
	if size > tailBytes {
		offset = size - tailBytes
	}
	buf := make([]byte, size-offset)
	if _, err := io.ReadFull(io.NewSectionReader(file, offset, int64(len(buf))), buf); err != nil {
		return ""
	}
	lines := strings.Split(strings.TrimRight(string(buf), "\n"), "\n")
	// Dropped before taking the last n, or a truncated read returns n-1 lines.
	if offset > 0 && len(lines) > 0 {
		lines = lines[1:]
	}
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}

func (c *checker) fetch(ctx context.Context, ref string) error {
	if _, err := os.Stat(filepath.Join(c.repoPath, ".git")); errors.Is(err, os.ErrNotExist) {
		url := fmt.Sprintf("ssh://%s@%s:%s/%s", *user, *gerritHost, *gerritPort, *project)
		if err := git(ctx, "", "clone", url, c.repoPath); err != nil {
			return fmt.Errorf("cloning %s: %w", url, err)
		}
	}
	if err := git(ctx, c.repoPath, "fetch", "origin", ref); err != nil {
		return fmt.Errorf("fetching %s: %w", ref, err)
	}
	if err := git(ctx, c.repoPath, "checkout", "--detach", "FETCH_HEAD"); err != nil {
		return fmt.Errorf("checking out %s: %w", ref, err)
	}
	// Nix builds what's in the working tree, so anything left behind by a
	// previous patch set would be evaluated as part of this one.
	if err := git(ctx, c.repoPath, "clean", "-xfd"); err != nil {
		return fmt.Errorf("cleaning the tree after checking out %s: %w", ref, err)
	}
	return nil
}

func git(ctx context.Context, dir string, args ...string) error {
	cmd := exec.CommandContext(ctx, "git", args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), fmt.Sprintf(
		"GIT_SSH_COMMAND=ssh -i '%s' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new", *keyFilePath))
	var stderr strings.Builder
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("git %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return nil
}

// pruneLogs drops logs old enough that the change they describe is long gone.
// Nothing links to them by then except a review message from another era.
func (c *checker) pruneLogs() error {
	entries, err := os.ReadDir(c.logsPath)
	if err != nil {
		return fmt.Errorf("reading %s: %w", c.logsPath, err)
	}
	for _, entry := range entries {
		info, err := entry.Info()
		if err != nil {
			continue
		}
		if time.Since(info.ModTime()) > *logMaxAge {
			os.Remove(filepath.Join(c.logsPath, entry.Name()))
		}
	}
	return nil
}

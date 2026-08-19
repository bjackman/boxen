// Package gerrit talks to the parts of Gerrit the agent workflow needs.
//
// It speaks two protocols, because Gerrit makes us: SSH for queries, reviews
// and administration, and REST for reading inline comments, which no SSH
// command returns. See design_docs/gerrit.md.
package gerrit

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"os"
	"os/exec"
	"strings"
	"time"
)

type Client struct {
	// SSH
	host    string
	port    int
	user    string
	keyFile string
	// REST, authenticated at the proxy rather than by Gerrit
	baseURL  string
	authUser string
	password string
	http     *http.Client
	loggedIn bool
}

type Config struct {
	Host         string
	Port         int
	User         string
	KeyFile      string
	BaseURL      string
	AuthUser     string
	PasswordFile string
}

func NewClient(config Config) (*Client, error) {
	password, err := os.ReadFile(config.PasswordFile)
	if err != nil {
		return nil, fmt.Errorf("reading proxy password: %w", err)
	}
	jar, err := cookiejar.New(nil)
	if err != nil {
		return nil, err
	}
	return &Client{
		host:     config.Host,
		port:     config.Port,
		user:     config.User,
		keyFile:  config.KeyFile,
		baseURL:  strings.TrimSuffix(config.BaseURL, "/"),
		authUser: config.AuthUser,
		password: strings.TrimSpace(string(password)),
		http:     &http.Client{Timeout: 30 * time.Second, Jar: jar},
	}, nil
}

type Account struct {
	Name     string `json:"name"`
	Username string `json:"username"`
	Email    string `json:"email"`
}

type PatchSet struct {
	Number   int    `json:"number"`
	Revision string `json:"revision"`
	// The ref this patch set can be fetched from, as refs/changes/NN/change/N.
	Ref string `json:"ref"`
}

type Change struct {
	Number          int      `json:"number"`
	ID              string   `json:"id"`
	Project         string   `json:"project"`
	Branch          string   `json:"branch"`
	Topic           string   `json:"topic"`
	Subject         string   `json:"subject"`
	URL             string   `json:"url"`
	Owner           Account  `json:"owner"`
	CurrentPatchSet PatchSet `json:"currentPatchSet"`
}

// Comment is a published inline comment. Gerrit's REST API reports these per
// file; the file is filled in from the map key.
type Comment struct {
	File      string
	ID        string  `json:"id"`
	Line      int     `json:"line"`
	Message   string  `json:"message"`
	Updated   string  `json:"updated"`
	Author    Account `json:"author"`
	InReplyTo string  `json:"in_reply_to"`
	PatchSet  int     `json:"patch_set"`
}

// ReviewInput is the subset of Gerrit's ReviewInput this workflow sets.
type ReviewInput struct {
	Message string `json:"message,omitempty"`
	// Keyed by file path. A reply carries InReplyTo; the file and line have to
	// match the comment being answered.
	Comments map[string][]CommentInput `json:"comments,omitempty"`
	// Without this nothing puts the reviewer back in the attention set: neither
	// a reply nor a new patch set does it on its own.
	AddToAttentionSet []AttentionSetInput `json:"add_to_attention_set,omitempty"`
	Labels            map[string]int      `json:"labels,omitempty"`
}

type AttentionSetInput struct {
	User   string `json:"user"`
	Reason string `json:"reason"`
}

func (c *Client) ssh(stdin string, args ...string) (string, error) {
	sshArgs := []string{
		"-i", c.keyFile,
		"-o", "IdentitiesOnly=yes",
		"-o", "StrictHostKeyChecking=accept-new",
		"-p", fmt.Sprint(c.port),
		fmt.Sprintf("%s@%s", c.user, c.host),
	}
	cmd := exec.Command("ssh", append(sshArgs, args...)...)
	if stdin != "" {
		cmd.Stdin = strings.NewReader(stdin)
	}
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("ssh %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return stdout.String(), nil
}

// Query runs `gerrit query`, dropping the trailing stats row.
func (c *Client) Query(terms ...string) ([]Change, error) {
	args := append([]string{"gerrit", "query", "--format=JSON", "--current-patch-set"}, terms...)
	out, err := c.ssh("", args...)
	if err != nil {
		return nil, err
	}
	var changes []Change
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		if line == "" {
			continue
		}
		var change Change
		if err := json.Unmarshal([]byte(line), &change); err != nil {
			return nil, fmt.Errorf("decoding query output: %w", err)
		}
		// The stats row has no number; it's the only row without one.
		if change.Number == 0 {
			continue
		}
		changes = append(changes, change)
	}
	return changes, nil
}

func (c *Client) Review(change int, patchSet int, review ReviewInput) error {
	encoded, err := json.Marshal(review)
	if err != nil {
		return err
	}
	_, err = c.ssh(string(encoded), "gerrit", "review", fmt.Sprintf("%d,%d", change, patchSet), "--json")
	return err
}

// Comments returns the published inline comments on a change, newest patch set
// included. No SSH command reports these: `gerrit query --comments` gives only
// the patch-set-level messages.
// login exchanges the proxy credential for a Gerrit session. The REST API under
// /a/ wants a credential of Gerrit's own, which the proxy has already consumed,
// and the plain paths are anonymous without a session - so this is the one way
// an API client authenticates as itself here.
func (c *Client) login() error {
	req, err := http.NewRequest("GET", c.baseURL+"/login/%2F", nil)
	if err != nil {
		return err
	}
	req.SetBasicAuth(c.authUser, c.password)
	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("logging in: %w", err)
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)
	if resp.StatusCode >= 400 {
		return fmt.Errorf("logging in: %s", http.StatusText(resp.StatusCode))
	}
	c.loggedIn = true
	return nil
}

func (c *Client) Comments(change int) ([]Comment, error) {
	if !c.loggedIn {
		if err := c.login(); err != nil {
			return nil, err
		}
	}
	path := fmt.Sprintf("/changes/%d/comments", change)
	req, err := http.NewRequest("GET", c.baseURL+path, nil)
	if err != nil {
		return nil, err
	}
	req.SetBasicAuth(c.authUser, c.password)

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("GET %s: %w", path, err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GET %s: %s: %s", path, http.StatusText(resp.StatusCode), truncate(string(body), 200))
	}

	var byFile map[string][]Comment
	if err := json.Unmarshal(stripMagic(body), &byFile); err != nil {
		return nil, fmt.Errorf("decoding comments: %w", err)
	}
	var comments []Comment
	for file, fileComments := range byFile {
		for _, comment := range fileComments {
			comment.File = file
			comments = append(comments, comment)
		}
	}
	return comments, nil
}

// Gerrit prefixes JSON responses with a magic line to break naive
// cross-site script inclusion.
func stripMagic(body []byte) []byte {
	const magic = ")]}'"
	if bytes.HasPrefix(body, []byte(magic)) {
		return bytes.TrimPrefix(bytes.TrimPrefix(body, []byte(magic)), []byte("\n"))
	}
	return body
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max] + "..."
}

// Event is the part of a stream-events record this workflow reads. The stream
// carries no comment bodies, so it's only ever a hint to go and look.
type Event struct {
	Type   string `json:"type"`
	Change struct {
		Number  int    `json:"number"`
		Project string `json:"project"`
		Topic   string `json:"topic"`
	} `json:"change"`
}

// StreamEvents calls onEvent for each event until the connection drops or the
// context is cancelled. It always returns an error: the stream ending is the
// only way out.
func (c *Client) StreamEvents(ctx context.Context, onEvent func(Event)) error {
	cmd := exec.CommandContext(ctx, "ssh",
		"-i", c.keyFile,
		"-o", "IdentitiesOnly=yes",
		"-o", "StrictHostKeyChecking=accept-new",
		// Notice a dead connection rather than blocking on it forever.
		"-o", "ServerAliveInterval=60",
		"-o", "ServerAliveCountMax=3",
		"-p", fmt.Sprint(c.port),
		fmt.Sprintf("%s@%s", c.user, c.host),
		"gerrit", "stream-events",
	)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for scanner.Scan() {
		var event Event
		if err := json.Unmarshal(scanner.Bytes(), &event); err != nil {
			// A record this doesn't understand is not a reason to tear the
			// stream down.
			continue
		}
		onEvent(event)
	}
	if err := cmd.Wait(); err != nil {
		return err
	}
	if err := scanner.Err(); err != nil {
		return err
	}
	return errors.New("event stream closed")
}

// Gerrit reports times in UTC, without a zone, to nanosecond precision.
const timeLayout = "2006-01-02 15:04:05.000000000"

func ParseTime(value string) (time.Time, error) {
	return time.Parse(timeLayout, strings.TrimSpace(value))
}

// CommentInput is a comment being written. Replying means setting InReplyTo to
// the id of the comment being answered, which threads it in the UI.
type CommentInput struct {
	Line      int    `json:"line,omitempty"`
	InReplyTo string `json:"in_reply_to,omitempty"`
	Message   string `json:"message"`
	// Whether the thread still needs the reviewer's attention. Resolving what
	// has actually been addressed is what makes the unresolved count mean
	// something.
	Unresolved bool `json:"unresolved"`
}

// Comment finds a published comment by id, so a reply can reuse its file and
// line. Gerrit has no endpoint for fetching one comment.
func (c *Client) Comment(change int, id string) (*Comment, error) {
	comments, err := c.Comments(change)
	if err != nil {
		return nil, err
	}
	for _, comment := range comments {
		if comment.ID == id {
			return &comment, nil
		}
	}
	return nil, fmt.Errorf("change %d has no comment %q", change, id)
}

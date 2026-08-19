// Package gerrit talks to the parts of Gerrit the agent workflow needs.
//
// It speaks two protocols, because Gerrit makes us: SSH for queries, reviews
// and administration, and REST for reading inline comments, which no SSH
// command returns. See design_docs/gerrit.md.
package gerrit

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
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
	return &Client{
		host:     config.Host,
		port:     config.Port,
		user:     config.User,
		keyFile:  config.KeyFile,
		baseURL:  strings.TrimSuffix(config.BaseURL, "/"),
		authUser: config.AuthUser,
		password: strings.TrimSpace(string(password)),
		http:     &http.Client{Timeout: 30 * time.Second},
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
func (c *Client) Comments(change int) ([]Comment, error) {
	path := fmt.Sprintf("/a/changes/%d/comments", change)
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

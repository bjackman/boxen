// Package forgejo talks to the parts of the Forgejo API that the agent
// workflow needs. It's hand-rolled rather than an SDK: the surface is a
// handful of endpoints, and the Gitea SDKs track a forge Forgejo has diverged
// from, at the cost of a vendor hash to maintain.
package forgejo

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

type Client struct {
	baseURL  string
	user     string
	password string
	http     *http.Client
}

func NewClient(baseURL, user, passwordFile string) (*Client, error) {
	password, err := os.ReadFile(passwordFile)
	if err != nil {
		return nil, fmt.Errorf("reading password: %w", err)
	}
	return &Client{
		baseURL:  strings.TrimSuffix(baseURL, "/"),
		user:     user,
		password: strings.TrimSpace(string(password)),
		http:     &http.Client{Timeout: 30 * time.Second},
	}, nil
}

type User struct {
	Login string `json:"login"`
}

type Label struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}

type PullRequest struct {
	Number int    `json:"number"`
	Title  string `json:"title"`
	Head   struct {
		Label string `json:"label"`
		SHA   string `json:"sha"`
	} `json:"head"`
	Labels    []Label `json:"labels"`
	Assignees []User  `json:"assignees"`
}

// Topic is the AGit topic this pull request was pushed under. The head label
// is "<pusher>/<topic>", where the pusher is whoever ran the push rather than
// the repository owner; head.ref is always refs/pull/<n>/head and carries
// nothing.
func (pr *PullRequest) Topic() string {
	if _, topic, found := strings.Cut(pr.Head.Label, "/"); found {
		return topic
	}
	return pr.Head.Label
}

func (pr *PullRequest) HasLabel(name string) bool {
	for _, label := range pr.Labels {
		if label.Name == name {
			return true
		}
	}
	return false
}

func (pr *PullRequest) AssigneeLogins() []string {
	logins := make([]string, 0, len(pr.Assignees))
	for _, assignee := range pr.Assignees {
		logins = append(logins, assignee.Login)
	}
	return logins
}

type APIError struct {
	Method string
	Path   string
	Status int
	Body   string
}

func (e *APIError) Error() string {
	body := strings.TrimSpace(e.Body)
	if len(body) > 200 {
		body = body[:200] + "..."
	}
	return fmt.Sprintf("%s %s: %s: %s", e.Method, e.Path, http.StatusText(e.Status), body)
}

func (c *Client) do(method, path string, body, out any) error {
	var payload io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return err
		}
		payload = bytes.NewReader(encoded)
	}

	req, err := http.NewRequest(method, c.baseURL+"/api/v1"+path, payload)
	if err != nil {
		return err
	}
	req.SetBasicAuth(c.user, c.password)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("%s %s: %w", method, path, err)
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("%s %s: %w", method, path, err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return &APIError{Method: method, Path: path, Status: resp.StatusCode, Body: string(data)}
	}
	if out != nil {
		if err := json.Unmarshal(data, out); err != nil {
			return fmt.Errorf("%s %s: decoding response: %w", method, path, err)
		}
	}
	return nil
}

// FindPullByTopic returns nil if no open pull request has this topic.
func (c *Client) FindPullByTopic(owner, repo, topic string) (*PullRequest, error) {
	var pulls []PullRequest
	path := fmt.Sprintf("/repos/%s/%s/pulls?state=open&limit=100", url.PathEscape(owner), url.PathEscape(repo))
	if err := c.do("GET", path, nil, &pulls); err != nil {
		return nil, err
	}
	for i := range pulls {
		if pulls[i].Topic() == topic {
			return &pulls[i], nil
		}
	}
	return nil, nil
}

func (c *Client) Pull(owner, repo string, number int) (*PullRequest, error) {
	var pr PullRequest
	path := fmt.Sprintf("/repos/%s/%s/pulls/%d", url.PathEscape(owner), url.PathEscape(repo), number)
	if err := c.do("GET", path, nil, &pr); err != nil {
		return nil, err
	}
	return &pr, nil
}

func (c *Client) Labels(owner, repo string) ([]Label, error) {
	var labels []Label
	path := fmt.Sprintf("/repos/%s/%s/labels", url.PathEscape(owner), url.PathEscape(repo))
	if err := c.do("GET", path, nil, &labels); err != nil {
		return nil, err
	}
	return labels, nil
}

func (c *Client) AddLabel(owner, repo string, number int, labelID int64) error {
	path := fmt.Sprintf("/repos/%s/%s/issues/%d/labels", url.PathEscape(owner), url.PathEscape(repo), number)
	return c.do("POST", path, map[string]any{"labels": []int64{labelID}}, nil)
}

// SetAssignees replaces the assignee list rather than adding to it.
func (c *Client) SetAssignees(owner, repo string, number int, logins []string) error {
	path := fmt.Sprintf("/repos/%s/%s/issues/%d", url.PathEscape(owner), url.PathEscape(repo), number)
	return c.do("PATCH", path, map[string]any{"assignees": logins}, nil)
}

package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/bjackman/boxen/go-tools/gerrit"
	"github.com/bjackman/boxen/go-tools/internal/review"
)

func change(number int, approvals []gerrit.Approval, messages ...gerrit.Message) gerrit.Change {
	return gerrit.Change{
		Number:          number,
		CurrentPatchSet: gerrit.PatchSet{Number: 1, Approvals: approvals},
		Messages:        messages,
	}
}

func byBot(text string) gerrit.Message {
	return gerrit.Message{Reviewer: gerrit.Account{Username: "review-bot"}, Message: text}
}

func TestPending(t *testing.T) {
	voted := []gerrit.Approval{{Type: review.Label, Value: "-1", By: gerrit.Account{Username: "review-bot"}}}
	byHuman := []gerrit.Approval{{Type: review.Label, Value: "2", By: gerrit.Account{Username: "brendan"}}}
	got := pending([]gerrit.Change{
		change(13, nil, byBot(review.RoundMessage(4, 5))),
		change(10, voted),
		change(11, byHuman),
		change(12, nil, byBot(review.RoundMessage(5, 5))),
	}, "review-bot", 5)

	var numbers []int
	for _, c := range got {
		numbers = append(numbers, c.Number)
	}
	if want := []int{11, 13}; len(numbers) != len(want) || numbers[0] != want[0] || numbers[1] != want[1] {
		t.Errorf("pending() = %v, want %v: unvoted and under the cap, oldest first", numbers, want)
	}
}

func TestPlace(t *testing.T) {
	repo := t.TempDir()
	if err := os.WriteFile(filepath.Join(repo, "a.nix"), []byte("one\ntwo\nthree"), 0o644); err != nil {
		t.Fatal(err)
	}
	files := []string{"a.nix", "gone.nix"}
	comments := place([]finding{
		{File: "a.nix", Line: 3, Message: "on a line"},
		{File: "a.nix", Line: 0, Message: "on the file"},
		{File: "a.nix", Line: 4, Message: "past the end"},
		{File: "untouched.nix", Line: 1, Message: "not in the change"},
		{File: "gone.nix", Line: 1, Message: "unreadable"},
		{File: "", Line: 0, Message: "on the change"},
	}, files, repo)

	onFile := comments["a.nix"]
	if len(onFile) != 2 || onFile[0].Line != 3 || onFile[1].Line != 0 {
		t.Errorf("comments on a.nix = %+v, want lines 3 and 0", onFile)
	}
	var whole []string
	for _, c := range comments[patchSetLevel] {
		whole = append(whole, c.Message)
	}
	want := []string{"a.nix:4: past the end", "untouched.nix:1: not in the change", "gone.nix:1: unreadable", "on the change"}
	if strings.Join(whole, "|") != strings.Join(want, "|") {
		t.Errorf("patch-set-level comments = %q, want %q", whole, want)
	}
	for path, cs := range comments {
		for _, c := range cs {
			if !c.Unresolved {
				t.Errorf("comment on %s is resolved; a finding needs answering", path)
			}
		}
	}
}

func TestParseOutput(t *testing.T) {
	got, err := parseOutput([]byte(`{"is_error":false,"result":"{}","structured_output":{"summary":"fine","findings":[{"file":"a.nix","line":1,"message":"m"}]}}`))
	if err != nil || got.Summary != "fine" || len(got.Findings) != 1 {
		t.Errorf("parseOutput() = %+v, %v", got, err)
	}
	for name, out := range map[string]string{
		"error":       `{"is_error":true,"result":"out of usage"}`,
		"no findings": `{"is_error":false,"result":"I refuse"}`,
		"not json":    `oops`,
	} {
		if _, err := parseOutput([]byte(out)); err == nil {
			t.Errorf("parseOutput() of %s succeeded", name)
		}
	}
}

func TestBuildPrompt(t *testing.T) {
	c := change(7, nil)
	c.PatchSets = []gerrit.PatchSet{{Number: 1, Comments: []gerrit.InlineComment{
		{File: "a.nix", Line: 2, Reviewer: gerrit.Account{Username: "slopbot"}, Message: "fixed"},
	}}}
	in := inputs{patch: "the diff"}

	first := buildPrompt(c, 1, 5, in)
	if !strings.Contains(first, "the diff") || strings.Contains(first, "fixed") {
		t.Errorf("round 1 prompt should have the diff and no history: %q", first)
	}
	if strings.Contains(first, "series") {
		t.Errorf("prompt mentions a series there isn't: %q", first)
	}
	later := buildPrompt(c, 2, 5, inputs{patch: "the diff", seriesPath: "/x/series.patch"})
	for _, want := range []string{"round 2 of 5", "[patch set 1, a.nix:2] slopbot: fixed", "/x/series.patch"} {
		if !strings.Contains(later, want) {
			t.Errorf("round 2 prompt is missing %q", want)
		}
	}
}

func TestFailureReason(t *testing.T) {
	notLoggedIn := `{"duration_api_ms":0,"stop_reason":"stop_sequence","usage":{"input_tokens":0,"output_tokens":0,"server_tool_use":{"web_search_requests":0}},"is_error":true,"result":"Not logged in · Please run /login"}`
	if got := failureReason([]byte(notLoggedIn), nil); got != "Not logged in · Please run /login" {
		t.Errorf("failureReason() = %q, want claude's own message", got)
	}
	if got := failureReason([]byte("not json"), []byte("segfault\n")); got != "segfault\nnot json" {
		t.Errorf("failureReason() without JSON = %q, want stderr then stdout", got)
	}
}

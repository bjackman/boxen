package main

import (
	"errors"
	"fmt"
	"testing"
)

func TestExitCode(t *testing.T) {
	published := &publishedError{url: "https://example.invalid/pulls/1", err: errors.New("labelling failed")}

	if got := exitCode(errors.New("could not push")); got != 1 {
		t.Errorf("exitCode of a pre-push failure = %d, want 1", got)
	}
	if got := exitCode(published); got != 2 {
		t.Errorf("exitCode of a post-push failure = %d, want 2", got)
	}
	// The wrapping matters: run() returns these from inside other error paths.
	if got := exitCode(fmt.Errorf("while finishing up: %w", published)); got != 2 {
		t.Errorf("exitCode of a wrapped post-push failure = %d, want 2", got)
	}
}

func TestProjectFromURL(t *testing.T) {
	for remote, want := range map[string]string{
		"ssh://slopbot@pizza:29418/boxen":     "boxen",
		"ssh://slopbot@pizza:29418/boxen.git": "boxen",
		"ssh://pizza:29418/nested/project/":   "nested/project",
	} {
		got, err := projectFromURL(remote)
		if err != nil {
			t.Errorf("projectFromURL(%q) failed: %v", remote, err)
		} else if got != want {
			t.Errorf("projectFromURL(%q) = %q, want %q", remote, got, want)
		}
	}
	for _, remote := range []string{"pizza:boxen", "/var/lib/claude/boxen", "ssh://pizza:29418/"} {
		if got, err := projectFromURL(remote); err == nil {
			t.Errorf("projectFromURL(%q) = %q, want an error", remote, got)
		}
	}
}

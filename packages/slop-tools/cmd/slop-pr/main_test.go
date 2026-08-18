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

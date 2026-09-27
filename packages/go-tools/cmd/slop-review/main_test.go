package main

import (
	"testing"

	"github.com/bjackman/boxen/go-tools/gerrit"
	"github.com/bjackman/boxen/go-tools/internal/review"
)

func TestReviewed(t *testing.T) {
	bot := gerrit.Account{Username: "review-bot"}
	vote := []gerrit.Approval{{Type: review.Label, Value: "-1", By: bot}}
	round := func(n int) []gerrit.Message {
		return []gerrit.Message{{Reviewer: bot, Message: review.RoundMessage(n, 5)}}
	}
	for _, test := range []struct {
		name   string
		change gerrit.Change
		want   bool
	}{
		{"voted", gerrit.Change{CurrentPatchSet: gerrit.PatchSet{Approvals: vote}, Messages: round(1)}, true},
		{"not yet", gerrit.Change{}, false},
		{"new patch set mid-way", gerrit.Change{Messages: round(3)}, false},
		{"out of rounds", gerrit.Change{Messages: round(5)}, true},
	} {
		if got := reviewed(test.change); got != test.want {
			t.Errorf("%s: reviewed() = %v, want %v", test.name, got, test.want)
		}
	}
}

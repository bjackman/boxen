package main

import (
	"testing"
	"time"

	"github.com/bjackman/boxen/slop-tools/internal/gerrit"
)

// The debounce exists so that reviewing a series of commits - which means
// publishing a review on each change in turn - is one agent run rather than
// one per change.
func TestDebounceHoldsRecentComments(t *testing.T) {
	for _, test := range []struct {
		name     string
		age      time.Duration
		debounce time.Duration
		ready    bool
	}{
		{"just posted", 5 * time.Second, 2 * time.Minute, false},
		{"still reviewing", 90 * time.Second, 2 * time.Minute, false},
		{"gone quiet", 3 * time.Minute, 2 * time.Minute, true},
	} {
		newest := time.Now().Add(-test.age)
		if ready := time.Since(newest) >= test.debounce; ready != test.ready {
			t.Errorf("%s: ready = %v, want %v", test.name, ready, test.ready)
		}
	}
}

func TestParseGerritTime(t *testing.T) {
	got, err := gerrit.ParseTime("2026-08-19 19:22:57.000000000")
	if err != nil {
		t.Fatalf("ParseTime: %v", err)
	}
	if want := time.Date(2026, 8, 19, 19, 22, 57, 0, time.UTC); !got.Equal(want) {
		t.Errorf("ParseTime() = %v, want %v", got, want)
	}
}

package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/bjackman/boxen/go-tools/gerrit"
)

func change(number, patchSet int, approvals ...gerrit.Approval) gerrit.Change {
	return gerrit.Change{
		Number:          number,
		CurrentPatchSet: gerrit.PatchSet{Number: patchSet, Approvals: approvals},
	}
}

func TestPending(t *testing.T) {
	mine := gerrit.Approval{Type: "Verified", Value: "1", By: gerrit.Account{Username: "ci-bot"}}
	review := gerrit.Approval{Type: "Code-Review", Value: "2", By: gerrit.Account{Username: "brendan"}}
	// Someone overriding the label by hand still counts as unverified: the
	// vote that means "checked" is this account's.
	byHand := gerrit.Approval{Type: "Verified", Value: "1", By: gerrit.Account{Username: "brendan"}}

	got := pending([]gerrit.Change{
		change(10, 1, mine),
		change(11, 3),
		change(12, 1, review),
		change(13, 2, byHand),
		change(14, 1, review, mine),
	}, "Verified", "ci-bot")

	var numbers []int
	for _, c := range got {
		numbers = append(numbers, c.Number)
	}
	want := []int{13, 12, 11}
	if len(numbers) != len(want) {
		t.Fatalf("pending() = %v, want %v", numbers, want)
	}
	for i := range want {
		if numbers[i] != want[i] {
			t.Fatalf("pending() = %v, want %v (newest first)", numbers, want)
		}
	}
}

func TestPendingNothingToDo(t *testing.T) {
	mine := gerrit.Approval{Type: "Verified", Value: "-1", By: gerrit.Account{Username: "ci-bot"}}
	if got := pending([]gerrit.Change{change(1, 1, mine)}, "Verified", "ci-bot"); len(got) != 0 {
		t.Errorf("pending() = %v, want none: a -1 is still a verdict", got)
	}
}

func TestMessage(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "log.txt")
	var lines []string
	for i := range 30 {
		lines = append(lines, "line "+string(rune('a'+i%26))+string(rune('0'+i/26)))
	}
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")), 0o644); err != nil {
		t.Fatal(err)
	}

	passed := message(nil, path, "https://logs/1-1.txt")
	if !strings.Contains(passed, "https://logs/1-1.txt") {
		t.Errorf("passing message has no log URL: %q", passed)
	}
	if strings.Contains(passed, lines[len(lines)-1]) {
		t.Errorf("passing message quotes the log, which nobody needs: %q", passed)
	}

	failed := message(errors.New("exit status 1"), path, "https://logs/1-1.txt")
	for _, want := range []string{"exit status 1", "https://logs/1-1.txt", lines[len(lines)-1]} {
		if !strings.Contains(failed, want) {
			t.Errorf("failing message missing %q: %q", want, failed)
		}
	}
	if strings.Contains(failed, lines[0]) {
		t.Errorf("failing message quotes the whole log, not the tail: %q", failed)
	}
}

// A failure that happens before anything is written must still report, or the
// change gets a vote with no explanation at all.
func TestMessageNoLog(t *testing.T) {
	failed := message(errors.New("boom"), filepath.Join(t.TempDir(), "absent.txt"), "https://logs/x.txt")
	if !strings.Contains(failed, "boom") || !strings.Contains(failed, "https://logs/x.txt") {
		t.Errorf("message() = %q, want the error and the URL", failed)
	}
}

func TestTail(t *testing.T) {
	path := filepath.Join(t.TempDir(), "log.txt")
	if err := os.WriteFile(path, []byte("one\ntwo\nthree\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got, want := tail(path, 2), "two\nthree"; got != want {
		t.Errorf("tail() = %q, want %q", got, want)
	}
	if got, want := tail(path, 10), "one\ntwo\nthree"; got != want {
		t.Errorf("tail() of a short file = %q, want %q", got, want)
	}
}

// A failing evaluation can print far more than anyone will read, and the
// excerpt must not pull all of it into memory.
func TestTailBoundsTheRead(t *testing.T) {
	path := filepath.Join(t.TempDir(), "big.txt")
	var b strings.Builder
	for i := range 200000 {
		fmt.Fprintf(&b, "line %d\n", i)
	}
	if err := os.WriteFile(path, []byte(b.String()), 0o644); err != nil {
		t.Fatal(err)
	}
	if info, err := os.Stat(path); err != nil || info.Size() <= tailBytes {
		t.Fatalf("test needs a file bigger than %d bytes", tailBytes)
	}

	got := tail(path, 3)
	if want := "line 199997\nline 199998\nline 199999"; got != want {
		t.Errorf("tail() = %q, want %q", got, want)
	}
	if strings.Contains(got, "line 0\n") {
		t.Errorf("tail() reached the start of the file: %q", got)
	}
}

func TestParsePatchSetName(t *testing.T) {
	number, patchSet, err := parsePatchSetName(patchSetName(123, 4))
	if err != nil || number != 123 || patchSet != 4 {
		t.Errorf("parsePatchSetName(patchSetName(123, 4)) = %d, %d, %v", number, patchSet, err)
	}
	for _, bad := range []string{"", "123", "123-", "x-1", "1-x"} {
		if _, _, err := parsePatchSetName(bad); err == nil {
			t.Errorf("parsePatchSetName(%q) succeeded, want an error", bad)
		}
	}
}

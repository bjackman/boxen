package session

import "testing"

// The value slop(1) produces:
//
//	uuidgen --sha1 --namespace @url --name boxen:test-topic
func TestIDMatchesUuidgen(t *testing.T) {
	const want = "6a1bcbe2-0e31-5698-b098-e7b7fdd0d462"
	if got := ID("boxen", "test-topic"); got != want {
		t.Errorf("ID(boxen, test-topic) = %q, want %q", got, want)
	}
}

func TestTranscriptFlattensWorkspacePath(t *testing.T) {
	const home = "/home/brendan"
	workspace := Workspace(home, "boxen", "fix-thing")
	if want := "/home/brendan/slop/boxen/fix-thing"; workspace != want {
		t.Fatalf("Workspace() = %q, want %q", workspace, want)
	}
	got := Transcript(home, workspace, "an-id")
	want := "/home/brendan/.claude/projects/-home-brendan-slop-boxen-fix-thing/an-id.jsonl"
	if got != want {
		t.Errorf("Transcript() = %q, want %q", got, want)
	}
}

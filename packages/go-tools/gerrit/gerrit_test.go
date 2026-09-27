package gerrit

import "testing"

func TestStripMagic(t *testing.T) {
	// Gerrit prefixes JSON responses to break cross-site script inclusion.
	got := string(stripMagic([]byte(")]}'\n{\"a\": 1}")))
	if want := `{"a": 1}`; got != want {
		t.Errorf("stripMagic() = %q, want %q", got, want)
	}
	if got := string(stripMagic([]byte(`{"a": 1}`))); got != `{"a": 1}` {
		t.Errorf("stripMagic() altered an unprefixed body: %q", got)
	}
}

func TestPatchSetVoted(t *testing.T) {
	ps := PatchSet{Approvals: []Approval{
		{Type: "Code-Review", Value: "2", By: Account{Username: "brendan"}},
		{Type: "Verified", Value: "-1", By: Account{Username: "ci-bot"}},
	}}
	for _, test := range []struct {
		label, user string
		want        bool
	}{
		{"Verified", "ci-bot", true},
		{"Verified", "brendan", false},
		{"Code-Review", "ci-bot", false},
		{"Submit", "ci-bot", false},
	} {
		if got := ps.Voted(test.label, test.user); got != test.want {
			t.Errorf("Voted(%q, %q) = %v, want %v", test.label, test.user, got, test.want)
		}
	}
}

func TestParseQueryWithComments(t *testing.T) {
	out := `{"number":84,"project":"boxen","comments":[{"timestamp":1790505550,"reviewer":{"username":"slopbot"},"message":"Uploaded patch set 1."}],"currentPatchSet":{"number":2,"ref":"refs/changes/84/84/2"},"patchSets":[{"number":1,"ref":"refs/changes/84/84/1","comments":[{"file":"flake.nix","line":3,"reviewer":{"username":"review-bot"},"message":"typo"}]},{"number":2,"ref":"refs/changes/84/84/2"}]}
{"type":"stats","rowCount":1}
`
	changes, err := parseQuery(out)
	if err != nil {
		t.Fatalf("parseQuery() failed: %v", err)
	}
	if len(changes) != 1 {
		t.Fatalf("parseQuery() = %d changes, want 1: the stats row isn't a change", len(changes))
	}
	change := changes[0]
	if change.CurrentPatchSet.Number != 2 || len(change.PatchSets) != 2 {
		t.Errorf("patch sets = current %d of %d, want current 2 of 2", change.CurrentPatchSet.Number, len(change.PatchSets))
	}
	if len(change.Messages) != 1 || change.Messages[0].Reviewer.Username != "slopbot" {
		t.Errorf("messages = %+v, want slopbot's upload", change.Messages)
	}
	if comments := change.PatchSets[0].Comments; len(comments) != 1 || comments[0].File != "flake.nix" || comments[0].Line != 3 || comments[0].Reviewer.Username != "review-bot" {
		t.Errorf("patch set 1 comments = %+v, want review-bot's on flake.nix:3", comments)
	}
}

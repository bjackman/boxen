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

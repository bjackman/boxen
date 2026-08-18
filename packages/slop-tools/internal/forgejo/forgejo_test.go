package forgejo

import "testing"

func TestPullRequestTopic(t *testing.T) {
	for _, test := range []struct {
		headLabel string
		want      string
	}{
		{"slopbot/fix-thing", "fix-thing"},
		{"brendan/fix-thing", "fix-thing"},
		{"fix-thing", "fix-thing"},
		{"slopbot/fix/thing", "fix/thing"},
	} {
		pr := PullRequest{}
		pr.Head.Label = test.headLabel
		if got := pr.Topic(); got != test.want {
			t.Errorf("Topic() of %q = %q, want %q", test.headLabel, got, test.want)
		}
	}
}

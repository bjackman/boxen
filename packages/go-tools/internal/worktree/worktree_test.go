package worktree

import "testing"

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

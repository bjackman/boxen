package probe

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

var journal = Probe{
	Command: "/nix/store/x-systemd/bin/journalctl",
	Args:    []string{"--no-pager", "--lines=1000"},
	Options: map[string]Option{
		"unit":    {Flag: "--unit", RegexpPattern: "[A-Za-z0-9@:._-]+"},
		"since":   {Flag: "--since", RegexpPattern: "[-+A-Za-z0-9 :,.]+"},
		"reverse": {Flag: "--reverse"},
	},
}

func TestArgvRendersFlagsInAStableOrder(t *testing.T) {
	got, err := journal.Argv(map[string]string{"since": "-1h", "unit": "sshd.service", "reverse": ""})
	if err != nil {
		t.Fatalf("Argv() = %v", err)
	}
	want := []string{
		"/nix/store/x-systemd/bin/journalctl", "--no-pager", "--lines=1000",
		"--reverse", "--since=-1h", "--unit=sshd.service",
	}
	if strings.Join(got, " ") != strings.Join(want, " ") {
		t.Errorf("Argv() = %q, want %q", got, want)
	}
}

// A value starting with "-" is the normal case for --since, so it has to reach
// the command as one argument rather than looking like another flag.
func TestArgvJoinsLongFlagsToTheirValue(t *testing.T) {
	got, err := journal.Argv(map[string]string{"since": "-1h"})
	if err != nil {
		t.Fatalf("Argv() = %v", err)
	}
	if last := got[len(got)-1]; last != "--since=-1h" {
		t.Errorf("Argv() last argument = %q, want %q", last, "--since=-1h")
	}
}

func TestArgvRejects(t *testing.T) {
	for _, tc := range []struct {
		name    string
		options map[string]string
		want    string
	}{
		{"unknown option", map[string]string{"vacuum-size": "1"}, "unknown option"},
		{"value for a switch", map[string]string{"reverse": "yes"}, "takes no value"},
		{"switch for a value option", map[string]string{"unit": ""}, "needs a value"},
		{"value the pattern forbids", map[string]string{"unit": "sshd.service --rotate"}, "not allowed"},
		{"a value that is only partly allowed", map[string]string{"unit": "ok\nrm -rf /"}, "not allowed"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := journal.Argv(tc.options)
			if err == nil {
				t.Fatalf("Argv(%v) succeeded, want an error", tc.options)
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Errorf("Argv(%v) = %q, want it to mention %q", tc.options, err, tc.want)
			}
		})
	}
}

func TestArgvRequiresRequiredOptions(t *testing.T) {
	status := Probe{
		Command: "/nix/store/x-systemd/bin/systemctl",
		Args:    []string{"status"},
		Options: map[string]Option{"unit": {Position: 1, RegexpPattern: "[a-z]+", Required: true}},
	}
	if _, err := status.Argv(nil); err == nil {
		t.Error("Argv() with no unit succeeded, want an error")
	}
	got, err := status.Argv(map[string]string{"unit": "sshd"})
	if err != nil {
		t.Fatalf("Argv() = %v", err)
	}
	if last := got[len(got)-1]; last != "sshd" {
		t.Errorf("Argv() last argument = %q, want the positional value", last)
	}
}

func TestArgvOrdersPositionalsByPosition(t *testing.T) {
	diff := Probe{
		Command: "/nix/store/x-nix/bin/nix",
		Args:    []string{"store", "diff-closures"},
		Options: map[string]Option{
			// Named so that alphabetical order is the wrong order.
			"to":   {Position: 2, RegexpPattern: "/nix/store/.+", Required: true},
			"from": {Position: 1, RegexpPattern: "/nix/store/.+", Required: true},
		},
	}
	got, err := diff.Argv(map[string]string{"from": "/nix/store/a", "to": "/nix/store/b"})
	if err != nil {
		t.Fatalf("Argv() = %v", err)
	}
	want := "/nix/store/x-nix/bin/nix store diff-closures /nix/store/a /nix/store/b"
	if strings.Join(got, " ") != want {
		t.Errorf("Argv() = %q, want %q", strings.Join(got, " "), want)
	}
}

func writeManifest(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "manifest.json")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

// Nix generates the manifests in practice, but nothing here knows that.
func TestLoadManifestTakesAnyAbsoluteCommand(t *testing.T) {
	path := writeManifest(t, `{"host":"h","probes":{"p":{"command":"/usr/bin/journalctl"}}}`)
	if _, err := LoadManifest(path); err != nil {
		t.Errorf("LoadManifest() = %v, want it to accept an absolute path", err)
	}
}

func TestLoadManifestRejectsARelativeCommand(t *testing.T) {
	path := writeManifest(t, `{"host":"h","probes":{"p":{"command":"journalctl"}}}`)
	if _, err := LoadManifest(path); err == nil {
		t.Error("LoadManifest() accepted a relative command, want an error")
	}
}

func TestLoadManifestRejectsAPatternItCannotCompile(t *testing.T) {
	path := writeManifest(t, `{"host":"h","probes":{"p":{"command":"/bin/true",
		"options":{"o":{"regexpPattern":"([a-z]"}}}}}`)
	if _, err := LoadManifest(path); err == nil {
		t.Error("LoadManifest() accepted an invalid pattern, want an error")
	}
}

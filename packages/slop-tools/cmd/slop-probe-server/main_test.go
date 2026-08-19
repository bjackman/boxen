package main

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/bjackman/boxen/slop-tools/internal/probe"
)

// The sandbox this runs in has /bin/sh and little else, so the probes here use
// it to stand in for the real store paths a generated manifest would name.
func manifestFile(t *testing.T, probes map[string]probe.Probe) string {
	t.Helper()
	raw, err := json.Marshal(probe.Manifest{Host: "testhost", Probes: probes})
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "manifest.json")
	if err := os.WriteFile(path, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func shell(script string) probe.Probe {
	return probe.Probe{
		Command:  "/bin/sh",
		Args:     []string{"-c", script},
		MaxBytes: 1 << 20,
		Timeout:  10,
	}
}

func invoke(t *testing.T, manifest string, request probe.Request) (int, string, string, error) {
	t.Helper()
	raw, err := json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	var stdout, stderr bytes.Buffer
	status, err := run(manifest, bytes.NewReader(raw), &stdout, &stderr, log.New(io.Discard, "", 0))
	return status, stdout.String(), stderr.String(), err
}

func TestRunsAProbe(t *testing.T) {
	manifest := manifestFile(t, map[string]probe.Probe{"hello": shell("echo hello")})
	status, stdout, _, err := invoke(t, manifest, probe.Request{Probe: "hello"})
	if err != nil || status != 0 {
		t.Fatalf("run() = %d, %v, want 0, nil", status, err)
	}
	if stdout != "hello\n" {
		t.Errorf("stdout = %q, want %q", stdout, "hello\n")
	}
}

func TestPassesThroughTheProbeExitStatus(t *testing.T) {
	manifest := manifestFile(t, map[string]probe.Probe{"nope": shell("exit 3")})
	status, _, _, err := invoke(t, manifest, probe.Request{Probe: "nope"})
	if err != nil {
		t.Fatalf("run() = %v", err)
	}
	// systemctl status uses its exit code to say what it found, so a non-zero
	// probe is not a failure of the mechanism.
	if status != 3 {
		t.Errorf("run() = %d, want 3", status)
	}
}

func TestRejectsAnUnknownProbe(t *testing.T) {
	manifest := manifestFile(t, map[string]probe.Probe{"hello": shell("echo hello")})
	status, _, _, err := invoke(t, manifest, probe.Request{Probe: "restart-everything"})
	if err == nil {
		t.Fatal("run() with an unknown probe succeeded, want an error")
	}
	if status != rejectedStatus {
		t.Errorf("run() = %d, want %d", status, rejectedStatus)
	}
}

func TestRejectsAnOptionTheProbeDoesNotDeclare(t *testing.T) {
	manifest := manifestFile(t, map[string]probe.Probe{"hello": shell("echo hello")})
	_, _, _, err := invoke(t, manifest, probe.Request{
		Probe:   "hello",
		Options: map[string]string{"rm": "-rf /"},
	})
	if err == nil {
		t.Fatal("run() with an undeclared option succeeded, want an error")
	}
}

func TestStopsAProbeThatFloods(t *testing.T) {
	flood := shell("while :; do echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; done")
	flood.MaxBytes = 4096
	flood.Timeout = 20
	manifest := manifestFile(t, map[string]probe.Probe{"flood": flood})

	status, stdout, stderr, err := invoke(t, manifest, probe.Request{Probe: "flood"})
	if err != nil {
		t.Fatalf("run() = %v", err)
	}
	// Not the status of the probe we killed, and in particular not ssh's 255.
	if status != abortedStatus {
		t.Errorf("run() = %d, want %d", status, abortedStatus)
	}
	if int64(len(stdout)) > flood.MaxBytes {
		t.Errorf("stdout was %d bytes, want at most %d", len(stdout), flood.MaxBytes)
	}
	if !strings.Contains(stderr, "narrow the query") {
		t.Errorf("stderr = %q, want it to say the output was cut short", stderr)
	}
}

func TestListDescribesTheHost(t *testing.T) {
	manifest := manifestFile(t, map[string]probe.Probe{"hello": shell("echo hello")})
	status, stdout, _, err := invoke(t, manifest, probe.Request{Probe: probe.ListProbe})
	if err != nil || status != 0 {
		t.Fatalf("run() = %d, %v, want 0, nil", status, err)
	}
	var got probe.Manifest
	if err := json.Unmarshal([]byte(stdout), &got); err != nil {
		t.Fatalf("list output is not a manifest: %v", err)
	}
	if got.Host != "testhost" {
		t.Errorf("list reported host %q, want %q", got.Host, "testhost")
	}
}

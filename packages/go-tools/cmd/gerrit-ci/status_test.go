package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestServeStatus(t *testing.T) {
	logsPath := t.TempDir()
	finished := time.Now().Add(-time.Hour)
	for _, r := range []record{
		{Change: 7, PatchSet: 1, Subject: "old pass", Started: finished.Add(-2 * time.Hour), Finished: finished.Add(-time.Hour), Vote: 1},
		{Change: 8, PatchSet: 2, Subject: "new fail", Started: finished.Add(-time.Minute), Finished: finished, Vote: -1,
			Checks: []checkResult{{Name: "pizza", Passed: true}, {Name: "fw13", Passed: false}}},
	} {
		if err := writeRecord(logsPath, &r); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(logsPath, "8-2.txt"), []byte("the log\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	st := &state{}
	st.setQueued([]queuedPatchSet{{Change: 10, PatchSet: 1, Subject: "waiting <here>"}})
	st.start(&record{Change: 9, PatchSet: 3, Subject: "in progress", Started: time.Now()})
	st.addResult(checkResult{Name: "pizza", Passed: true})
	handler := newServer(logsPath, st, "https://gerrit.example").handler()

	resp := httptest.NewRecorder()
	handler.ServeHTTP(resp, httptest.NewRequest("GET", "/", nil))
	if resp.Code != http.StatusOK {
		t.Fatalf("GET / = %d: %s", resp.Code, resp.Body)
	}
	page := resp.Body.String()
	for _, want := range []string{
		`href="https://gerrit.example/c/boxen/&#43;/9/3"`, "in progress", "1 check(s) done",
		"waiting &lt;here&gt;",
		"fw13 failed", `href="8-2.txt"`,
	} {
		if !strings.Contains(page, want) {
			t.Errorf("status page lacks %q:\n%s", want, page)
		}
	}
	if strings.Index(page, "new fail") > strings.Index(page, "old pass") {
		t.Errorf("recent runs aren't newest first:\n%s", page)
	}

	resp = httptest.NewRecorder()
	handler.ServeHTTP(resp, httptest.NewRequest("GET", "/8-2.txt", nil))
	if resp.Body.String() != "the log\n" {
		t.Errorf("GET /8-2.txt = %d %q, want the log", resp.Code, resp.Body)
	}
}

func TestServeStatusEmpty(t *testing.T) {
	resp := httptest.NewRecorder()
	newServer(t.TempDir(), &state{}, "https://gerrit.example").handler().ServeHTTP(resp, httptest.NewRequest("GET", "/", nil))
	if resp.Code != http.StatusOK || strings.Count(resp.Body.String(), "Nothing") != 3 {
		t.Errorf("GET / with nothing to show = %d:\n%s", resp.Code, resp.Body)
	}
}

func TestRoughDuration(t *testing.T) {
	for d, want := range map[time.Duration]string{
		45 * time.Second:              "45s",
		5*time.Minute + 3*time.Second: "5m03s",
		26*time.Hour + 7*time.Minute:  "26h07m",
		14 * 24 * time.Hour:           "14d",
	} {
		if got := roughDuration(d); got != want {
			t.Errorf("roughDuration(%v) = %q, want %q", d, got, want)
		}
	}
}

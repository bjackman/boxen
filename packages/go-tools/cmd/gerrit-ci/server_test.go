package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestCheckRuns(t *testing.T) {
	started := time.Date(2026, 10, 2, 12, 0, 0, 0, time.UTC)
	records := []record{
		{Change: 7, PatchSet: 1, Started: started, Finished: started.Add(time.Minute), Vote: 1,
			Checks: []checkResult{{Name: "pizza", Passed: true}}},
		{Change: 7, PatchSet: 2, Started: started, Finished: started.Add(time.Minute), Vote: -1,
			Checks: []checkResult{{Name: "pizza", Passed: true}, {Name: "fw13", Passed: false}}},
		{Change: 7, PatchSet: 3, Started: started, Finished: started.Add(time.Minute), Vote: -1,
			Error: "listing checks failed"},
	}
	running := &record{Change: 7, PatchSet: 4, Started: started, Checks: []checkResult{{Name: "pizza", Passed: true}}}
	queued := []queuedPatchSet{{Change: 8, PatchSet: 1}, {Change: 7, PatchSet: 5}}

	runs := checkRuns(records, running, queued, 7)
	byPatchSet := map[int]checkRun{}
	for _, run := range runs {
		byPatchSet[run.Patchset] = run
	}
	if len(runs) != 5 || len(byPatchSet) != 5 {
		t.Fatalf("checkRuns() = %+v, want one run for each of patch sets 1-5", runs)
	}

	if got := byPatchSet[5].Status; got != "SCHEDULED" {
		t.Errorf("queued patch set has status %q", got)
	}
	if got := byPatchSet[4]; got.Status != "RUNNING" || got.FinishedTimestamp != nil {
		t.Errorf("running patch set = %+v, want RUNNING and unfinished", got)
	}
	if got := byPatchSet[1]; got.Status != "COMPLETED" || len(got.Results) != 0 {
		t.Errorf("passing patch set = %+v, want COMPLETED with no results", got)
	}
	if got := byPatchSet[2].Results; len(got) != 1 || got[0].Category != "ERROR" || got[0].Summary != "fw13 failed to build" {
		t.Errorf("failing patch set results = %+v, want one ERROR for fw13", got)
	}
	if got := byPatchSet[3].Results; len(got) != 1 || got[0].Summary != "listing checks failed" {
		t.Errorf("errored patch set results = %+v, want the error", got)
	}
	for _, run := range runs {
		if run.CheckName != checkName || run.LabelName != "Verified" {
			t.Errorf("run %+v isn't named %q against Verified", run, checkName)
		}
	}
}

// A patch set being checked again after an error has a record from last time,
// which is stale once it's queued or running again.
func TestCheckRunsSupersedeRecord(t *testing.T) {
	records := []record{{Change: 7, PatchSet: 1, Error: "fetch failed"}}

	runs := checkRuns(records, &record{Change: 7, PatchSet: 1}, nil, 7)
	if len(runs) != 1 || runs[0].Status != "RUNNING" {
		t.Errorf("checkRuns() while running = %+v, want just the running one", runs)
	}

	runs = checkRuns(records, nil, []queuedPatchSet{{Change: 7, PatchSet: 1}}, 7)
	if len(runs) != 1 || runs[0].Status != "SCHEDULED" {
		t.Errorf("checkRuns() while queued = %+v, want just the queued one", runs)
	}
}

func TestServeChecks(t *testing.T) {
	logsPath := t.TempDir()
	if err := writeRecord(logsPath, &record{Change: 12, PatchSet: 1, Vote: 1, Started: time.Now()}); err != nil {
		t.Fatal(err)
	}
	// Another change whose number shares a prefix, which mustn't show up.
	if err := writeRecord(logsPath, &record{Change: 123, PatchSet: 1, Vote: 1}); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(logsPath, "12-1.txt"), []byte("the log\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	srv := &server{logsPath: logsPath, state: &state{}, allowOrigin: "https://gerrit.example"}
	handler := srv.handler()

	resp := httptest.NewRecorder()
	handler.ServeHTTP(resp, httptest.NewRequest("GET", "/api/checks/12", nil))
	if resp.Code != http.StatusOK {
		t.Fatalf("GET /api/checks/12 = %d: %s", resp.Code, resp.Body)
	}
	if got := resp.Header().Get("Access-Control-Allow-Origin"); got != "https://gerrit.example" {
		t.Errorf("Access-Control-Allow-Origin = %q", got)
	}
	if got := resp.Header().Get("Access-Control-Allow-Credentials"); got != "true" {
		t.Errorf("Access-Control-Allow-Credentials = %q, but the IAP needs the session cookie", got)
	}
	var body struct {
		Runs []checkRun `json:"runs"`
	}
	if err := json.Unmarshal(resp.Body.Bytes(), &body); err != nil {
		t.Fatalf("parsing %s: %v", resp.Body, err)
	}
	if len(body.Runs) != 1 || body.Runs[0].Patchset != 1 || body.Runs[0].Status != "COMPLETED" {
		t.Errorf("runs = %+v, want change 12's one completed run", body.Runs)
	}

	resp = httptest.NewRecorder()
	handler.ServeHTTP(resp, httptest.NewRequest("GET", "/12-1.txt", nil))
	if resp.Code != http.StatusOK || resp.Body.String() != "the log\n" {
		t.Errorf("GET /12-1.txt = %d %q, want the log: review messages link there", resp.Code, resp.Body)
	}

	resp = httptest.NewRecorder()
	handler.ServeHTTP(resp, httptest.NewRequest("GET", "/api/checks/nope", nil))
	if resp.Code != http.StatusBadRequest {
		t.Errorf("GET /api/checks/nope = %d, want 400", resp.Code)
	}
}

// An empty list must encode as [], not null: the plugin passes it straight to
// Gerrit.
func TestServeChecksNoRuns(t *testing.T) {
	srv := &server{logsPath: t.TempDir(), state: &state{}}
	resp := httptest.NewRecorder()
	srv.handler().ServeHTTP(resp, httptest.NewRequest("GET", "/api/checks/1", nil))
	if got, want := resp.Body.String(), "{\"runs\":[]}\n"; got != want {
		t.Errorf("body = %q, want %q", got, want)
	}
}

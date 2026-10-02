package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"sync"
	"time"
)

type checkResult struct {
	Name   string `json:"name"`
	Passed bool   `json:"passed"`
}

// record is what the runner remembers about checking one patch set, for
// display only. Whether a patch set still needs checking is decided by its
// vote in Gerrit, never by these.
type record struct {
	Change   int           `json:"change"`
	PatchSet int           `json:"patchSet"`
	Subject  string        `json:"subject"`
	Started  time.Time     `json:"started"`
	Finished time.Time     `json:"finished,omitzero"`
	Vote     int           `json:"vote,omitempty"`
	Checks   []checkResult `json:"checks"`
	// Why the run stopped short of a result for every check.
	Error string `json:"error,omitempty"`
}

func (r *record) name() string {
	return patchSetName(r.Change, r.PatchSet)
}

type queuedPatchSet struct {
	Change   int
	PatchSet int
}

// state is what the runner is doing right now, shared with the HTTP server.
type state struct {
	mu      sync.Mutex
	running *record
	queued  []queuedPatchSet
}

func (s *state) setQueued(queued []queuedPatchSet) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.queued = queued
}

func (s *state) start(r *record) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.running = r
	s.queued = slices.DeleteFunc(s.queued, func(q queuedPatchSet) bool { return q.Change == r.Change })
}

func (s *state) addResult(result checkResult) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.running != nil {
		s.running.Checks = append(s.running.Checks, result)
	}
}

func (s *state) finish() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.running = nil
}

// snapshot returns a copy of the running record, if any, and of the queue.
func (s *state) snapshot() (*record, []queuedPatchSet) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var running *record
	if s.running != nil {
		r := *s.running
		r.Checks = slices.Clone(r.Checks)
		running = &r
	}
	return running, slices.Clone(s.queued)
}

func writeRecord(logsPath string, r *record) error {
	data, err := json.Marshal(r)
	if err != nil {
		return fmt.Errorf("encoding the record of %s: %w", r.name(), err)
	}
	path := filepath.Join(logsPath, r.name()+".json")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return fmt.Errorf("writing %s: %w", path, err)
	}
	return nil
}

// readRecords returns the finished records of every patch set of a change.
func readRecords(logsPath string, change int) ([]record, error) {
	paths, err := filepath.Glob(filepath.Join(logsPath, strconv.Itoa(change)+"-*.json"))
	if err != nil {
		return nil, fmt.Errorf("listing the records of change %d: %w", change, err)
	}
	var records []record
	for _, path := range paths {
		data, err := os.ReadFile(path)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, fmt.Errorf("reading %s: %w", path, err)
		}
		var r record
		if err := json.Unmarshal(data, &r); err != nil {
			return nil, fmt.Errorf("parsing %s: %w", path, err)
		}
		records = append(records, r)
	}
	return records, nil
}

// The types below are the subset of the Gerrit frontend's Checks API that this
// runner fills in, so that the plugin can hand them to Gerrit unchanged. See
// polygerrit-ui/app/api/checks.ts in the Gerrit source.

type checkRun struct {
	Patchset          int           `json:"patchset"`
	CheckName         string        `json:"checkName"`
	LabelName         string        `json:"labelName"`
	Status            string        `json:"status"`
	StatusDescription string        `json:"statusDescription,omitempty"`
	StatusLink        string        `json:"statusLink,omitempty"`
	StartedTimestamp  *time.Time    `json:"startedTimestamp,omitempty"`
	FinishedTimestamp *time.Time    `json:"finishedTimestamp,omitempty"`
	Results           []checkOutput `json:"results,omitempty"`
}

type checkOutput struct {
	Category string      `json:"category"`
	Summary  string      `json:"summary"`
	Links    []checkLink `json:"links,omitempty"`
}

type checkLink struct {
	URL     string `json:"url"`
	Primary bool   `json:"primary"`
	Icon    string `json:"icon"`
}

// The one run this runner reports per patch set. One per flake check would
// show more, but which checks there are isn't known until the patch set has
// been evaluated, and a run's name is its identity across states.
const checkName = "nix build"

// checkRuns returns the runs of one change. A patch set that is queued or
// running again after an error still has a record of that error, which is
// superseded and left out.
func checkRuns(records []record, running *record, queued []queuedPatchSet, change int) []checkRun {
	runs := []checkRun{}
	current := map[int]bool{}
	for _, q := range queued {
		if q.Change == change {
			runs = append(runs, checkRun{Patchset: q.PatchSet, CheckName: checkName, LabelName: *label, Status: "SCHEDULED"})
			current[q.PatchSet] = true
		}
	}
	if running != nil && running.Change == change {
		run := toCheckRun(running)
		run.Status = "RUNNING"
		run.StatusDescription = fmt.Sprintf("%d check(s) done", len(running.Checks))
		runs = append(runs, run)
		current[running.PatchSet] = true
	}
	for _, r := range records {
		if !current[r.PatchSet] {
			runs = append(runs, toCheckRun(&r))
		}
	}
	return runs
}

func toCheckRun(r *record) checkRun {
	logLink := checkLink{URL: logURLFor(r.name()), Primary: true, Icon: "history"}
	run := checkRun{
		Patchset:         r.PatchSet,
		CheckName:        checkName,
		LabelName:        *label,
		Status:           "COMPLETED",
		StatusLink:       logLink.URL,
		StartedTimestamp: &r.Started,
	}
	if !r.Finished.IsZero() {
		run.FinishedTimestamp = &r.Finished
	}
	var passed []string
	for _, check := range r.Checks {
		if check.Passed {
			passed = append(passed, check.Name)
			continue
		}
		run.Results = append(run.Results, checkOutput{
			Category: "ERROR", Summary: check.Name + " failed to build", Links: []checkLink{logLink},
		})
	}
	if r.Error != "" {
		run.Results = append(run.Results, checkOutput{
			Category: "ERROR", Summary: r.Error, Links: []checkLink{logLink},
		})
	}
	if len(passed) > 0 {
		run.StatusDescription = fmt.Sprintf("%d check(s) built", len(passed))
	}
	return run
}

type server struct {
	logsPath string
	state    *state
	// The Gerrit web UI's origin, which the Checks plugin fetches from.
	allowOrigin string
}

func (s *server) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/checks/{change}", s.serveChecks)
	mux.Handle("GET /", http.FileServer(http.Dir(s.logsPath)))
	return mux
}

func (s *server) serveChecks(w http.ResponseWriter, req *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", s.allowOrigin)
	w.Header().Set("Access-Control-Allow-Credentials", "true")

	change, err := strconv.Atoi(req.PathValue("change"))
	if err != nil {
		http.Error(w, fmt.Sprintf("bad change number %q", req.PathValue("change")), http.StatusBadRequest)
		return
	}
	records, err := readRecords(s.logsPath, change)
	if err != nil {
		log.Printf("serving checks for change %d: %v", change, err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	running, queued := s.state.snapshot()
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(map[string]any{"runs": checkRuns(records, running, queued, change)}); err != nil {
		log.Printf("writing checks for change %d: %v", change, err)
	}
}

package main

import (
	_ "embed"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

//go:embed status.html
var statusHTML string

// recentLimit is how many finished runs the status page lists.
const recentLimit = 50

type statusPage struct {
	Project string
	Running *record
	Queued  []queuedPatchSet
	Recent  []record
	MaxAge  string
}

func statusTemplate(gerritURL string) *template.Template {
	return template.Must(template.New("status").Funcs(template.FuncMap{
		"changeURL": func(change, patchSet int) string {
			return fmt.Sprintf("%s/c/%s/+/%d/%d", gerritURL, *project, change, patchSet)
		},
		"logPath": func(change, patchSet int) string {
			return patchSetName(change, patchSet) + ".txt"
		},
		"since": func(t time.Time) string { return roughDuration(time.Since(t)) },
		"took":  func(r record) string { return roughDuration(r.Finished.Sub(r.Started)) },
		"problems": func(r record) string {
			var problems []string
			for _, check := range r.Checks {
				if !check.Passed {
					problems = append(problems, check.Name+" failed")
				}
			}
			if r.Error != "" {
				problems = append(problems, r.Error)
			}
			return strings.Join(problems, "; ")
		},
	}).Parse(statusHTML))
}

func roughDuration(d time.Duration) string {
	switch {
	case d < time.Minute:
		return fmt.Sprintf("%ds", int(d.Seconds()))
	case d < time.Hour:
		return fmt.Sprintf("%dm%02ds", int(d.Minutes()), int(d.Seconds())%60)
	case d < 48*time.Hour:
		return fmt.Sprintf("%dh%02dm", int(d.Hours()), int(d.Minutes())%60)
	default:
		return fmt.Sprintf("%dd", int(d.Hours()/24))
	}
}

// recentRecords returns the most recently finished records, newest first.
func recentRecords(logsPath string, n int) ([]record, error) {
	records, err := readRecordFiles(filepath.Join(logsPath, "*.json"))
	if err != nil {
		return nil, err
	}
	slices.SortFunc(records, func(a, b record) int { return b.Finished.Compare(a.Finished) })
	if len(records) > n {
		records = records[:n]
	}
	return records, nil
}

func (s *server) serveStatus(w http.ResponseWriter, req *http.Request) {
	recent, err := recentRecords(s.logsPath, recentLimit)
	if err != nil {
		log.Printf("serving the status page: %v", err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	running, queued := s.state.snapshot()
	page := statusPage{Project: *project, Running: running, Queued: queued, Recent: recent, MaxAge: roughDuration(*logMaxAge)}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := s.status.Execute(w, page); err != nil {
		log.Printf("rendering the status page: %v", err)
	}
}

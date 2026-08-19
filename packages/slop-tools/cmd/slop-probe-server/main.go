// slop-probe-server is the forced command behind the probe user's SSH key. It
// reads a request on stdin - the client's command line is never consulted, so
// nothing the caller composes is parsed as a command here - looks the probe up
// in a Nix-generated manifest, and runs it. See design_docs/agent_prod_access.md.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"log/syslog"
	"os"
	"os/exec"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/bjackman/boxen/slop-tools/internal/probe"
)

// Statuses of our own, above anything a probe produces and clear of ssh's own
// 255, so that a caller can tell "you asked for something you can't have" and
// "you got less than you asked for" apart from a probe that ran and failed.
const (
	rejectedStatus = 111
	abortedStatus  = 112
)

func main() {
	manifestPath := flag.String("manifest", "", "Path to the JSON probe manifest")
	flag.Parse()

	audit := openAudit()
	status, err := run(*manifestPath, os.Stdin, os.Stdout, os.Stderr, audit)
	if err != nil {
		fmt.Fprintf(os.Stderr, "slop-probe-server: %v\n", err)
		audit.Printf("rejected: %v", err)
	}
	os.Exit(status)
}

// openAudit returns a logger writing to the journal, so that `journalctl -t
// slop-probe` on the host is a record of everything an agent looked at. A host
// without a working syslog socket shouldn't stop the probe working, so failure
// here is silent.
func openAudit() *log.Logger {
	writer, err := syslog.New(syslog.LOG_INFO|syslog.LOG_AUTHPRIV, "slop-probe")
	if err != nil {
		return log.New(io.Discard, "", 0)
	}
	return log.New(writer, "", 0)
}

func run(manifestPath string, stdin io.Reader, stdout, stderr io.Writer, audit *log.Logger) (int, error) {
	if manifestPath == "" {
		return rejectedStatus, errors.New("no --manifest given")
	}
	manifest, err := probe.LoadManifest(manifestPath)
	if err != nil {
		return rejectedStatus, err
	}

	var request probe.Request
	if err := json.NewDecoder(stdin).Decode(&request); err != nil {
		return rejectedStatus, fmt.Errorf("reading request: %w", err)
	}
	audit.Printf("client=%s probe=%s options=%s", os.Getenv("SSH_CLIENT"), request.Probe, describe(request.Options))

	if request.Probe == probe.ListProbe {
		encoder := json.NewEncoder(stdout)
		encoder.SetIndent("", "  ")
		return 0, encoder.Encode(manifest)
	}

	p, ok := manifest.Probes[request.Probe]
	if !ok {
		return rejectedStatus, fmt.Errorf("unknown probe %q on %s, try the `list` probe", request.Probe, manifest.Host)
	}
	argv, err := p.Argv(request.Options)
	if err != nil {
		return rejectedStatus, err
	}

	status, err := execute(p, argv, stdout, stderr)
	audit.Printf("probe=%s status=%d", request.Probe, status)
	return status, err
}

func describe(options map[string]string) string {
	var parts []string
	for name, value := range options {
		parts = append(parts, fmt.Sprintf("%s=%q", name, value))
	}
	return strings.Join(parts, " ")
}

func execute(p probe.Probe, argv []string, stdout, stderr io.Writer) (int, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(p.Timeout)*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	// A probe is a whole pipeline's worth of work in some cases; killing the
	// group means a timeout doesn't leave children behind.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	cmd.WaitDelay = 5 * time.Second
	cmd.Env = []string{
		"PATH=/run/current-system/sw/bin",
		"LC_ALL=C",
		"SYSTEMD_COLORS=0",
		"TERM=dumb",
	}

	limit := &limiter{max: p.MaxBytes, stop: cancel}
	cmd.Stdout = limit.wrap(stdout)
	cmd.Stderr = limit.wrap(stderr)

	err := cmd.Run()

	// Reported rather than silently truncated: half a journal that looks whole
	// is worse to reason from than a short answer plus a hint. The probe's own
	// status is meaningless once we've killed it, hence a status of our own.
	switch {
	case limit.exceeded():
		fmt.Fprintf(stderr, "\nslop-probe-server: output stopped at %d bytes, narrow the query\n", p.MaxBytes)
		return abortedStatus, nil
	case ctx.Err() != nil:
		fmt.Fprintf(stderr, "\nslop-probe-server: probe killed after %ds\n", p.Timeout)
		return abortedStatus, nil
	}

	var exit *exec.ExitError
	switch {
	case err == nil:
		return 0, nil
	case errors.As(err, &exit):
		if code := exit.ExitCode(); code >= 0 {
			return code, nil
		}
		// Killed by something other than us, so report it the way a shell
		// would rather than as exec's -1.
		if status, ok := exit.Sys().(syscall.WaitStatus); ok && status.Signaled() {
			return 128 + int(status.Signal()), nil
		}
		return abortedStatus, nil
	default:
		return rejectedStatus, err
	}
}

// limiter caps the total bytes a probe may emit across both streams, and stops
// the probe once it has.
type limiter struct {
	max  int64
	stop func()

	mu      sync.Mutex
	written int64
	hit     bool
}

func (l *limiter) wrap(w io.Writer) io.Writer {
	return writerFunc(func(p []byte) (int, error) {
		l.mu.Lock()
		room := l.max - l.written
		if room > int64(len(p)) {
			room = int64(len(p))
		}
		if room < 0 {
			room = 0
		}
		l.written += room
		full := l.written >= l.max
		if full {
			l.hit = true
		}
		l.mu.Unlock()

		if room > 0 {
			if _, err := w.Write(p[:room]); err != nil {
				return 0, err
			}
		}
		if full {
			l.stop()
		}
		// The probe is told it wrote everything: it has no say in the cap, and
		// a short write would just make it report an error of its own.
		return len(p), nil
	})
}

func (l *limiter) exceeded() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.hit
}

type writerFunc func([]byte) (int, error)

func (f writerFunc) Write(p []byte) (int, error) { return f(p) }

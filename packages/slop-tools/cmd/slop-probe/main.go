// slop-probe runs one of a homelab host's declared probes and streams the
// output, so that an agent investigating prod can pipe it through the usual
// shell tools instead of swallowing it whole. It is deliberately the only
// access an agent has to those hosts; what the probes are is decided in
// nixos_modules/slop-probe.nix. See design_docs/agent_prod_access.md.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"

	"github.com/bjackman/boxen/slop-tools/internal/probe"
)

// Set at build time; the defaults are only useful for `go run`.
var (
	sshUser        = "slopbot"
	keyFile        = "/run/agenix/slopbot-probe-ssh-privkey"
	knownHostsFile = "/etc/ssh/ssh_known_hosts"
	hosts          = "pizza,norte"
)

const usage = `Usage:
  slop-probe <host> <probe> [--option=value | --option value | --switch]...
  slop-probe <host> list
  slop-probe hosts

Probes are read-only and declared in the host's NixOS config. If the one you
need doesn't exist, propose it as a pull request rather than looking for a way
around this.

The exit status is the probe's own, except: 111 if the host refused the
request, 112 if it stopped the probe for taking too long or saying too much,
255 if the connection failed.`

func main() {
	if err := run(os.Args[1:]); err != nil {
		// A status from the far end means it has already said what was wrong
		// on stderr, and repeating it here just buries that.
		var exit *exec.ExitError
		if errors.As(err, &exit) {
			os.Exit(exit.ExitCode())
		}
		fmt.Fprintf(os.Stderr, "slop-probe: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	known := strings.Split(hosts, ",")
	if len(args) == 1 && args[0] == "hosts" {
		fmt.Println(strings.Join(known, "\n"))
		return nil
	}
	if len(args) < 2 {
		return errors.New(usage)
	}
	host, name := args[0], args[1]
	if !contains(known, host) {
		return fmt.Errorf("no probes on %q, hosts are: %s", host, strings.Join(known, ", "))
	}
	options, err := parseOptions(args[2:])
	if err != nil {
		return err
	}
	request, err := json.Marshal(probe.Request{Probe: name, Options: options})
	if err != nil {
		return err
	}

	cmd := exec.Command("ssh", sshArgs(host)...)
	cmd.Stdin = bytes.NewReader(request)
	cmd.Stderr = os.Stderr
	// The manifest is JSON so that a caller can pipe it into jq, but reading it
	// is the main use, so plain `list` renders it.
	if name == probe.ListProbe && !contains(args[2:], "--json") {
		var out bytes.Buffer
		cmd.Stdout = &out
		if err := cmd.Run(); err != nil {
			return err
		}
		return describe(&out)
	}
	cmd.Stdout = os.Stdout
	return cmd.Run()
}

func sshArgs(host string) []string {
	return []string{
		"-T",
		"-o", "BatchMode=yes",
		"-o", "ConnectTimeout=10",
		"-o", "IdentitiesOnly=yes",
		"-o", "StrictHostKeyChecking=yes",
		"-o", "UserKnownHostsFile=" + knownHostsFile,
		"-i", keyFile,
		"-l", sshUser,
		host,
	}
}

// parseOptions accepts --name=value, --name value and a bare --name for
// switches. There are no positional arguments at this level - a probe's
// positional parameters are named options too - so a token that doesn't start
// with "--" can only be the preceding option's value.
func parseOptions(args []string) (map[string]string, error) {
	options := map[string]string{}
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if !strings.HasPrefix(arg, "--") {
			return nil, fmt.Errorf("expected an option, got %q", arg)
		}
		name, value, split := strings.Cut(strings.TrimPrefix(arg, "--"), "=")
		if name == "" {
			return nil, fmt.Errorf("malformed option %q", arg)
		}
		if !split && i+1 < len(args) && !strings.HasPrefix(args[i+1], "--") {
			value, i = args[i+1], i+1
		}
		if _, seen := options[name]; seen {
			return nil, fmt.Errorf("option %q given twice", name)
		}
		options[name] = value
	}
	return options, nil
}

func describe(manifest *bytes.Buffer) error {
	var m probe.Manifest
	if err := json.Unmarshal(manifest.Bytes(), &m); err != nil {
		return fmt.Errorf("parsing the manifest: %w", err)
	}
	fmt.Printf("Probes on %s:\n", m.Host)
	for _, name := range sorted(m.Probes) {
		p := m.Probes[name]
		fmt.Printf("\n  %s - %s\n", name, p.Description)
		for _, optName := range sorted(p.Options) {
			opt := p.Options[optName]
			spec := "--" + optName
			if !opt.IsSwitch() {
				spec += "=" + placeholder(opt)
			}
			if opt.Required {
				spec += " (required)"
			}
			fmt.Printf("      %-40s %s\n", spec, opt.Description)
		}
	}
	return nil
}

// placeholder shows the pattern, since knowing what a probe will accept is
// most of what the caller needs from `list`.
func placeholder(opt probe.Option) string {
	if len(opt.RegexpPattern) > 30 {
		return opt.RegexpPattern[:30] + "..."
	}
	return opt.RegexpPattern
}

func sorted[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func contains(haystack []string, needle string) bool {
	for _, s := range haystack {
		if s == needle {
			return true
		}
	}
	return false
}

// Package slopflags defines the configuration flags slop-tools.nix wraps every
// slop tool with. It's one list for all of them, so each tool has to accept
// every flag on it whether it uses it or not.
package slopflags

import (
	"flag"
	"fmt"
	"strconv"

	"github.com/bjackman/boxen/go-tools/gerrit"
)

type Config struct {
	GerritHost       string
	GerritPort       string
	GerritURL        string
	Pusher           string
	Reviewer         string
	Branch           string
	KeyFilePath      string
	AuthUser         string
	PasswordFilePath string
}

func Register(flags *flag.FlagSet) *Config {
	c := &Config{}
	flags.StringVar(&c.GerritHost, "gerrit-host", "pizza", "Gerrit host to talk to")
	flags.StringVar(&c.GerritPort, "gerrit-port", "29418", "Gerrit SSH port")
	flags.StringVar(&c.GerritURL, "gerrit-url", "https://gerrit.home.yawn.io", "Gerrit web base URL")
	flags.StringVar(&c.Pusher, "pusher", "slopbot", "Gerrit account the agent works as")
	flags.StringVar(&c.Reviewer, "reviewer", "brendan", "Reviewer to add to the agent's changes")
	flags.StringVar(&c.Branch, "branch", "master", "Branch changes are proposed against")
	flags.StringVar(&c.KeyFilePath, "key-file", "/run/agenix/slopbot-ssh-privkey", "Path to the SSH private key")
	flags.StringVar(&c.AuthUser, "auth-user", "slopbot", "User to authenticate to the proxy as")
	flags.StringVar(&c.PasswordFilePath, "password-file", "/run/agenix/slopbot-authelia-password", "Path to the file holding the proxy password")
	return c
}

// Client talks to Gerrit as the pusher.
func (c *Config) Client() (*gerrit.Client, error) {
	port, err := strconv.Atoi(c.GerritPort)
	if err != nil {
		return nil, fmt.Errorf("parsing --gerrit-port %q: %w", c.GerritPort, err)
	}
	client, err := gerrit.NewClient(gerrit.Config{
		Host: c.GerritHost, Port: port, User: c.Pusher, KeyFile: c.KeyFilePath,
		BaseURL: c.GerritURL, AuthUser: c.AuthUser, PasswordFile: c.PasswordFilePath,
	})
	if err != nil {
		return nil, fmt.Errorf("creating Gerrit client for %s:%d: %w", c.GerritHost, port, err)
	}
	return client, nil
}

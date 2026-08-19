// slop-reply answers one review comment, threaded under it, and marks the
// thread resolved unless told otherwise.
//
// This exists so the agent can respond point by point as it works, the way a
// person does, rather than leaving one summary that the reviewer has to map
// back onto their comments themselves.
package main

import (
	"flag"
	"fmt"
	"os"
	"strconv"

	"github.com/bjackman/boxen/slop-tools/internal/gerrit"
)

// Set at build time.
var (
	gerritHost   = "pizza"
	gerritPort   = "29418"
	gerritURL    = "https://gerrit.home.yawn.io"
	pusher       = "slopbot"
	keyFile      = "/run/agenix/slopbot-ssh-privkey"
	authUser     = "slopbot"
	passwordFile = "/run/agenix/slopbot-authelia-password"
)

var unresolved = flag.Bool("unresolved", false,
	"leave the thread open, for a reply that doesn't settle it")

func main() {
	flag.Usage = func() {
		fmt.Fprintln(os.Stderr, "usage: slop-reply [--unresolved] <change> <comment-id> <message>")
		flag.PrintDefaults()
	}
	flag.Parse()
	if err := run(flag.Args()); err != nil {
		fmt.Fprintf(os.Stderr, "slop-reply: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) != 3 {
		flag.Usage()
		return fmt.Errorf("expected a change, a comment id and a message")
	}
	change, err := strconv.Atoi(args[0])
	if err != nil {
		return fmt.Errorf("bad change number %q: %w", args[0], err)
	}
	commentID, message := args[1], args[2]

	port, err := strconv.Atoi(gerritPort)
	if err != nil {
		return fmt.Errorf("bad gerritPort %q: %w", gerritPort, err)
	}
	client, err := gerrit.NewClient(gerrit.Config{
		Host: gerritHost, Port: port, User: pusher, KeyFile: keyFile,
		BaseURL: gerritURL, AuthUser: authUser, PasswordFile: passwordFile,
	})
	if err != nil {
		return err
	}

	// The reply has to sit on the same file and line as what it answers.
	comment, err := client.Comment(change, commentID)
	if err != nil {
		return err
	}

	patchSet, err := currentPatchSet(client, change)
	if err != nil {
		return err
	}

	return client.Review(change, patchSet, gerrit.ReviewInput{
		Comments: map[string][]gerrit.CommentInput{
			comment.File: {{
				Line:       comment.Line,
				InReplyTo:  commentID,
				Message:    message,
				Unresolved: *unresolved,
			}},
		},
	})
}

func currentPatchSet(client *gerrit.Client, change int) (int, error) {
	changes, err := client.Query("change:" + strconv.Itoa(change))
	if err != nil {
		return 0, err
	}
	if len(changes) == 0 {
		return 0, fmt.Errorf("no change %d", change)
	}
	return changes[0].CurrentPatchSet.Number, nil
}

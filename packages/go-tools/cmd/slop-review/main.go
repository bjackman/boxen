// slop-review asks review-bot to review the agent's changes, waits for it, and
// prints what it found with the ids slop-reply answers them by. See
// design_docs/review_bot.md.
//
// The review is fetched rather than delivered: nothing can put a message into
// a running session, but the session can run this and read what it prints.
package main

import (
	"flag"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/bjackman/boxen/go-tools/gerrit"
	"github.com/bjackman/boxen/go-tools/internal/review"
	"github.com/bjackman/boxen/go-tools/internal/slopflags"
	"github.com/bjackman/boxen/go-tools/internal/worktree"
)

var (
	config    = slopflags.Register(flag.CommandLine)
	reviewBot = flag.String("review-bot", "review-bot", "Gerrit account that reviews")
	timeout   = flag.Duration("timeout", 30*time.Minute, "how long to wait for the reviews")
	pollFreq  = flag.Duration("poll", 15*time.Second, "how often to check whether they've arrived")
)

func main() {
	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(), "usage: slop-review [flags] [change...]\n\n"+
			"Get review-bot's review of the given changes, or of every open change in the\n"+
			"worktree's topic, and print its findings.\n\n")
		flag.PrintDefaults()
	}
	flag.Parse()
	if err := run(flag.Args()); err != nil {
		fmt.Fprintf(os.Stderr, "slop-review: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	client, err := config.Client()
	if err != nil {
		return err
	}
	numbers, err := changesToReview(client, args)
	if err != nil {
		return err
	}
	for _, number := range numbers {
		if err := client.AddReviewer(number, *reviewBot); err != nil {
			return fmt.Errorf("adding %s to change %d: %w", *reviewBot, number, err)
		}
	}

	deadline := time.Now().Add(*timeout)
	for {
		changes, err := query(client, numbers)
		if err != nil {
			return err
		}
		var waiting []gerrit.Change
		for _, change := range changes {
			if !reviewed(change) {
				waiting = append(waiting, change)
			}
		}
		if len(waiting) == 0 {
			return printReviews(client, changes)
		}
		if time.Now().After(deadline) {
			for _, change := range waiting {
				fmt.Printf("Change %d patch set %d hasn't been reviewed after %v.\n",
					change.Number, change.CurrentPatchSet.Number, *timeout)
				if msg := latestMessage(change); msg != "" {
					fmt.Printf("%s's last message on it:\n%s\n", *reviewBot, indent(msg))
				}
			}
			return fmt.Errorf("gave up waiting for %s on %d of %d changes", *reviewBot, len(waiting), len(changes))
		}
		time.Sleep(*pollFreq)
	}
}

func changesToReview(client *gerrit.Client, args []string) ([]int, error) {
	var numbers []int
	for _, arg := range args {
		number, err := strconv.Atoi(arg)
		if err != nil {
			return nil, fmt.Errorf("parsing change number %q: %w", arg, err)
		}
		numbers = append(numbers, number)
	}
	if len(numbers) > 0 {
		return numbers, nil
	}
	project, topic, err := worktree.Topic()
	if err != nil {
		return nil, err
	}
	changes, err := client.Query("status:open", "project:"+project, "topic:"+topic)
	if err != nil {
		return nil, fmt.Errorf("querying open changes in topic %s: %w", topic, err)
	}
	if len(changes) == 0 {
		return nil, fmt.Errorf("no open changes in topic %s of %s; run slop-pr first", topic, project)
	}
	for _, change := range changes {
		numbers = append(numbers, change.Number)
	}
	sort.Ints(numbers)
	return numbers, nil
}

func query(client *gerrit.Client, numbers []int) ([]gerrit.Change, error) {
	var terms []string
	for _, number := range numbers {
		if len(terms) > 0 {
			terms = append(terms, "OR")
		}
		terms = append(terms, "change:"+strconv.Itoa(number))
	}
	changes, err := client.QueryWithComments(terms...)
	if err != nil {
		return nil, fmt.Errorf("querying changes %v: %w", numbers, err)
	}
	sort.Slice(changes, func(i, j int) bool { return changes[i].Number < changes[j].Number })
	return changes, nil
}

// reviewed is whether there's nothing more to wait for: the current patch set
// has the bot's vote, or the bot has done all the rounds it will.
func reviewed(change gerrit.Change) bool {
	if change.CurrentPatchSet.Voted(review.Label, *reviewBot) {
		return true
	}
	done, maxRounds := review.Rounds(change.Messages, *reviewBot)
	return maxRounds > 0 && done >= maxRounds
}

func latestMessage(change gerrit.Change) string {
	for i := len(change.Messages) - 1; i >= 0; i-- {
		if change.Messages[i].Reviewer.Username == *reviewBot {
			return change.Messages[i].Message
		}
	}
	return ""
}

func printReviews(client *gerrit.Client, changes []gerrit.Change) error {
	findings := 0
	for _, change := range changes {
		patchSet := change.CurrentPatchSet
		fmt.Printf("Change %d patch set %d: %s\n", change.Number, patchSet.Number, change.URL)
		if !patchSet.Voted(review.Label, *reviewBot) {
			done, _ := review.Rounds(change.Messages, *reviewBot)
			fmt.Printf("  Not reviewed: %s has done all %d of its rounds on this change, so the rest is for a human.\n\n",
				*reviewBot, done)
			continue
		}
		fmt.Println(indent(latestMessage(change)))

		comments, err := client.Comments(change.Number)
		if err != nil {
			return fmt.Errorf("reading the comments on change %d: %w", change.Number, err)
		}
		sort.Slice(comments, func(i, j int) bool {
			if comments[i].File != comments[j].File {
				return comments[i].File < comments[j].File
			}
			return comments[i].Line < comments[j].Line
		})
		for _, comment := range comments {
			if comment.Author.Username != *reviewBot || comment.PatchSet != patchSet.Number {
				continue
			}
			where := comment.File
			if where == "/PATCHSET_LEVEL" {
				where = "the change as a whole"
			} else if comment.Line > 0 {
				where += ":" + strconv.Itoa(comment.Line)
			}
			fmt.Printf("  [%s] %s: %s\n", comment.ID, where, comment.Message)
			findings++
		}
		fmt.Println()
	}
	if findings > 0 {
		fmt.Printf("Answer each finding with `slop-reply <change> <comment-id> <message>`, " +
			"with --unresolved where you disagree.\n")
	}
	return nil
}

func indent(s string) string {
	return "  " + strings.ReplaceAll(strings.TrimSpace(s), "\n", "\n  ")
}

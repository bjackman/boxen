// Package review is what review-bot and slop-review, which asks for its
// reviews, agree on: the vote, and how a round is recorded on the change so
// that either can count them without keeping state of its own.
package review

import (
	"fmt"
	"regexp"
	"strconv"

	"github.com/bjackman/boxen/go-tools/gerrit"
)

const Label = "Code-Review"

func RoundMessage(round, maxRounds int) string {
	return fmt.Sprintf("Review round %d of %d.", round, maxRounds)
}

var roundPattern = regexp.MustCompile(`Review round (\d+) of (\d+)\.`)

// Rounds reads back the latest RoundMessage user left on a change: how many
// rounds it has done, and how many it allows. Both are zero before the first.
func Rounds(messages []gerrit.Message, user string) (done, maxRounds int) {
	for _, message := range messages {
		if message.Reviewer.Username != user {
			continue
		}
		match := roundPattern.FindStringSubmatch(message.Message)
		if match == nil {
			continue
		}
		round, _ := strconv.Atoi(match[1])
		allowed, _ := strconv.Atoi(match[2])
		if round >= done {
			done, maxRounds = round, allowed
		}
	}
	return done, maxRounds
}

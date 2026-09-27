package review

import (
	"testing"

	"github.com/bjackman/boxen/go-tools/gerrit"
)

func message(user, text string) gerrit.Message {
	return gerrit.Message{Reviewer: gerrit.Account{Username: user}, Message: text}
}

func TestRounds(t *testing.T) {
	for _, test := range []struct {
		name          string
		messages      []gerrit.Message
		done, allowed int
	}{
		{"none yet", []gerrit.Message{message("slopbot", "Uploaded patch set 1.")}, 0, 0},
		{
			"latest wins, as Gerrit formats it",
			[]gerrit.Message{
				message("review-bot", "Patch Set 1: Code-Review-1\n\n(2 comments)\n\n"+RoundMessage(1, 5)+" Two problems."),
				message("slopbot", "Uploaded patch set 2."),
				message("review-bot", "Patch Set 2: Code-Review+1\n\n"+RoundMessage(2, 5)),
			},
			2, 5,
		},
		{
			"only its own",
			[]gerrit.Message{message("brendan", "Patch Set 1:\n\n> "+RoundMessage(4, 5)+"\n\nNo it isn't.")},
			0, 0,
		},
	} {
		done, allowed := Rounds(test.messages, "review-bot")
		if done != test.done || allowed != test.allowed {
			t.Errorf("%s: Rounds() = %d of %d, want %d of %d", test.name, done, allowed, test.done, test.allowed)
		}
	}
}

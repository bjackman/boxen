# Review bot

**Status: implemented, not yet enabled.**

## Goals

1. Every change the agent uploads gets an independent automated review before
   it reaches me.
1. The Gerrit UI shows whether the current patch set has had that review.
1. The findings get back to the agent that wrote the change, without any
   machinery for delivering messages into a running session.

Not goals: gating submission on the bot, or reviewing every change whether or
not anyone asked.

## Background

### How the agent works

The agent runs on `pizza` under `claude remote-control`, one session per git
worktree of `boxen`, the worktree named for the session. `slop-pr` uploads the
worktree's commits with the worktree name as the Gerrit topic; `slop-reply`
answers a comment by id. Review comments reach the agent because I pass it
their ids in the session.

### `slop-handler` was the previous answer

It followed Gerrit's event stream on `slopbox` and resumed the session for a
topic, under `~/slop/<repo>/<topic>`, with the comments on its changes. It
can't reach remote-control sessions, which live on another host, and left
running it would answer comments on their changes by starting a second agent
with none of the context. It's retired alongside this.

### Nothing can push a message into a session

Claude Code 2.1.283 has no command that sends a message into a running
session, and this build has no channels. A watcher could run a throwaway
`claude -p` to relay one with `SendMessage`, whose behaviour for an idle or
offline session is undocumented, or `claude --bg --resume` a session, which
copies it if it's running and otherwise runs it where I'm not looking. None of
that is needed if the agent fetches its review instead of being sent it.

## Decisions

1. **The agent pulls; nothing is pushed.** It runs `slop-review` after
   `slop-pr`. That adds `review-bot` as a reviewer on the topic's changes,
   waits for its votes, and prints the findings with their comment ids. The
   command's output is the delivery.

1. **The reviewer is a separate service, as its own user.** `review-bot` on
   `pizza`, not a child of the agent's session. Two things depend on that:

   - *Its identity means something.* Its SSH key is readable only by its own
     user, so the agent can't post as it, and a vote from it can be trusted -
     enough to gate submission on later, if that's ever wanted.
   - *It's independent.* A `claude -p` started by the agent runs as the agent's
     user, and loads that user's instructions and memory. The reviewer starts
     from an empty home instead.

   It asks for nothing new from Gerrit: being added as a reviewer is the
   request, and `reviewer-added` is the event it wakes on, so anyone can ask
   for a review of any change the same way.

1. **Same subscription, its own token.** The agent's credentials file is a
   short-lived OAuth token that Claude Code refreshes and rewrites; a second
   user sharing it would lose access at the first rewrite, and two refreshers
   of one login can log each other out. `claude setup-token` issues a
   long-lived token for the same account, which the service gets as
   `CLAUDE_CODE_OAUTH_TOKEN`.

1. **The reviewer can read, and nothing else.** `claude -p --restricted
   --tools Read,Grep,Glob --strict-mcp-config`: no Bash, file access confined
   to the checkout and its inputs, and settings files and MCP servers ignored,
   so nothing the change adds to the checkout can widen that. The service
   works out the diffs itself rather than letting the reviewer run `git`.

1. **One review per change, with the series as context.** The change's commit
   message and diff are in the prompt; the commits below it in the series are
   in a file beside the checkout. A finding goes on the change that introduces
   the problem.

1. **It votes `Code-Review` ±1.** -1 with findings, +1 without. The vote is
   what shows "reviewed" in the UI: it isn't copied to a patch set with code
   changes, so a current patch set without it hasn't been reviewed.
   `Code-Review` because it needs no configuration and can't affect
   submission: the requirement is `label:Code-Review=MAX AND
   -label:Code-Review=MIN`, which only a +2 satisfies and only a -2 blocks.

1. **Up to five rounds, then it's mine.** While it's a reviewer, every new
   patch set is reviewed, so after the agent answers a round the next happens
   without being asked. From the second round the reviewer sees what has been
   said so far and doesn't raise answered points again. If the two agents
   haven't converged after five rounds, they're not going to without me.

   The rounds are counted from the "Review round N of M." that starts each of
   its messages, so neither side keeps any state of its own. A finding the
   agent disagrees with is answered with `--unresolved`, and
   `No-Unresolved-Comments` holds the change until I've read the argument.

1. **Failures are said on the change.** A review that fails is reported the
   first time and retried, and the patch set is given up on after three
   failures until the service restarts. `slop-review` gives up after half an
   hour and prints the bot's last message on each change it was waiting for.

## Design

### `review-bot`

`packages/go-tools/cmd/review-bot`, run by `nixos_modules/review-bot.nix`. Its
loop is `gerrit-ci`'s: the event stream wakes it, a sweep every five minutes
catches what the stream missed, and a patch set is pending when it has no vote
from `review-bot` and its change has had fewer than five rounds. Per patch set:

1. Fetch it and the destination branch into its own clone.
1. Write the series below it to a file.
1. Run the restricted `claude -p` with the change in the prompt, and the
   earlier rounds' comments from the second round on, and have it return a
   summary and findings against a JSON schema.
1. Post the findings as unresolved inline comments with the vote. Gerrit
   rejects a whole review over one comment on a file the change doesn't touch
   or a line the file doesn't have, so a finding that can't be placed where it
   says goes on the change as a whole instead.

### `slop-review`

`packages/go-tools/cmd/slop-review`, in `slop-tools`. With no arguments it
works on every open change in the worktree's topic. It prints, per change, the
bot's message and each finding as `[comment-id] file:line: message`, or says
that the change is out of rounds.

### Gerrit

`review-bot` is created by `gerrit-bootstrap` like `ci-bot`, in `Service
Users`, with its public key derived from the secret, so there is only one copy
of the key to make. `Registered Users` already hold `Code-Review` -1..+1.

## Enabling it

The key has to be generated by me rather than the agent, and the token needs a
browser login, so switching it on is manual:

1. `ssh-keygen -t ed25519 -C review-bot@gerrit -f key && agenix -e
   review-bot-ssh-privkey.age < key && rm key key.pub`
1. `claude setup-token`, then `agenix -e review-bot-claude-env.age` holding
   `CLAUDE_CODE_OAUTH_TOKEN=<token>`.
1. `bjackman.reviewBot.enable = true;` for `pizza`, and the instruction to run
   `slop-review` after `slop-pr` in `hm_modules/pizza-claude.nix`.

## Open questions

- **Model and cost.** Tested with the default model: a small change took 16 s
  and peaked at 290 MB. Real changes will take longer; the unit allows 20
  minutes and 1.5 GB.
- **Relaying my own comments** is still by hand. A `slop-comments` that lists
  a topic's unresolved threads with their ids would make "address the
  comments on 82" the whole instruction.

## Addendum: alternatives discussed and parked

Recorded so they don't have to be worked out again. None of them changes the
design above.

### Messaging between sessions

Messaging between sessions already exists from inside a session: an agent has
`ListAgents` and `SendMessage` tools, backed by a per-process socket under
`/tmp/cc-socks/`. What's missing is a way for an outside process, like
`review-bot`, to send a message into a running session; if Claude Code gains
one, it would remove `slop-review`'s wait, and - the bigger win - let comments
from me wake the session that wrote the change, which is what `slop-handler`
was for.

If it lands, use it as a doorbell: the message says only "review-bot voted on
change 102, run `slop-review`" or "Brendan commented on 84", and the content
is still fetched from Gerrit. The agent session runs with permissions
bypassed, and a channel carrying text from a service that reads untrusted
diffs would be a route for prompt injection into it. A lost message then also
loses nothing.

Two snags. `claude-remote-control` runs with `PrivateTmp=true`, so a service
in another unit can't reach the sockets; the doorbell would have to run inside
that unit, as `claude`, watching the event stream. And the session to ring is
found from the topic only through an undocumented naming scheme: topic
`bridge-cse_01Loq…` is session `bridge-cse-01loq…-fe` to `ListAgents`.

### A persistent reviewer

A long-lived reviewer session would remember its earlier rounds rather than
reconstructing them from the threads, and as a Remote Control session I could
question and steer it from the app. Against it:

- Something would have to deliver work into it - the problem this design
  avoids by starting a fresh `claude -p` per review.
- Every review reads untrusted diffs. A fresh process confines an injection
  to one review; a long-lived session carries it into the reviews of other
  changes.
- Its context grows across changes, and it anchors on its own earlier
  verdicts.
- A hung session means no reviews until someone notices; the service starts
  clean every time and recovers its work from Gerrit.

If later rounds turn out to lose the thread, the cheaper fix is a session per
change: give each change's reviewer a fixed session id on its first round and
`claude -p --resume` it on the next. That keeps memory across rounds with no
long-lived process and no messaging, and still confines an injection to one
change. One small test change's second round rebuilt its context from the
threads fine, so this waits for evidence.

Steering is better done with a review guidelines file beside `CLAUDE.md`,
reviewed like any other change, than by talking to a session.

### The Claude Agent SDK

It only sends messages into sessions it runs itself: `ClaudeSDKClient` keeps
one open within a process, and `resume` or `fork` starts a new run from a
saved transcript, which is `claude -p --resume` as a library. It can't
attach to a session running in another process, so it doesn't help with
getting findings to the agent. It would make a persistent reviewer practical,
since the service would own the session it feeds, but the objections above
still apply; and it's Python or TypeScript beside Go tools. (From the
documentation, not tested.)

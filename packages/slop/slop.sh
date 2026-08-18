
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "usage: slop <topic> [repo]" >&2
    exit 1
fi

topic=$1
repo=${2:-boxen}
worktree="$HOME/slop/$repo/$topic"

# The whole workflow hangs off this being stable: the same topic always means
# the same session, so review comments land back in the conversation that
# produced the change. See design_docs/agent_prs.md.
session_id=$(uuidgen --sha1 --namespace @url --name "$repo:$topic")
transcript="$HOME/.claude/projects/$(echo "$worktree" | tr '/.' '--')/$session_id.jsonl"

if [ ! -e "$worktree" ]; then
    mkdir -p "$(dirname "$worktree")"
    git clone -c "core.sshCommand=ssh -i $key_file -o IdentitiesOnly=yes" \
        "$forgejo_ssh/$owner/$repo.git" "$worktree"
fi

# --session-id refuses to reuse an existing id, so which flag to pass depends on
# whether this change has been worked on before.
if [ -e "$transcript" ]; then
    claude_args=(--resume "$session_id")
else
    claude_args=(--session-id "$session_id")
fi

# tmux so the session outlives the SSH connection, which is what makes it
# reachable over Remote Control.
exec tmux new-session -A -s "slop-$repo-$topic" -c "$worktree" \
    claude --permission-mode bypassPermissions "${claude_args[@]}"

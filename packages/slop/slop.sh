
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "usage: slop <topic> [project]" >&2
    exit 1
fi

topic=$1
project=${2:-boxen}
worktree="$HOME/slop/$project/$topic"

# The whole workflow hangs off this being stable: the same topic always means
# the same session, so review comments land back in the conversation that
# produced the change. See design_docs/gerrit.md.
session_id=$(uuidgen --sha1 --namespace @url --name "$project:$topic")
transcript="$HOME/.claude/projects/$(echo "$worktree" | tr '/.' '--')/$session_id.jsonl"

ssh_command="ssh -i $key_file -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

if [ ! -e "$worktree" ]; then
    mkdir -p "$(dirname "$worktree")"
    GIT_SSH_COMMAND="$ssh_command" \
        git clone -c "core.sshCommand=$ssh_command" \
        "ssh://$pusher@$gerrit_host:$gerrit_port/$project" "$worktree"
    # Gerrit identifies a change by a Change-Id trailer, which this hook adds.
    # Over SSH rather than /tools/hooks/commit-msg, which is behind the proxy's
    # authentication.
    $ssh_command -p "$gerrit_port" "$pusher@$gerrit_host" \
        gerrit hook commit-msg > "$worktree/.git/hooks/commit-msg"
    chmod +x "$worktree/.git/hooks/commit-msg"
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
exec tmux new-session -A -s "slop-$project-$topic" -c "$worktree" \
    claude --permission-mode bypassPermissions "${claude_args[@]}"

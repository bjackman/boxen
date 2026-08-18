
root=$(git rev-parse --show-toplevel)
topic=$(basename "$root")
repo=$(basename "$(dirname "$root")")
api_url="$forgejo_url/api/v1"

api() {
    local method=$1 path=$2
    shift 2
    curl -sS --fail-with-body -u "slopbot:$(cat "$password_file")" \
        -X "$method" -H 'Content-Type: application/json' "$api_url$path" "$@"
}

# AGit pull requests carry their topic in head.label, prefixed by whoever
# pushed rather than by the repo owner. head.ref is always refs/pull/<n>/head
# and says nothing.
pr_number() {
    api GET "/repos/$owner/$repo/pulls?state=open" \
        | jq -r --arg topic "$topic" \
            '.[] | select((.head.label | sub("^[^/]+/"; "")) == $topic) | .number' \
        | head -1
}

number=$(pr_number)

if [ -z "$number" ]; then
    # Only sent on creation: repeating it on every update would clobber a title
    # edited in the web UI.
    title=${1:-$(git log --format=%s "origin/master..HEAD" | tail -1)}
    git push origin HEAD:refs/for/master \
        -o "topic=$topic" -o force-push=true -o "title=$title"
    number=$(pr_number)
    if [ -z "$number" ]; then
        echo "pushed, but no pull request appeared for topic $topic" >&2
        exit 1
    fi
elif [ "$(api GET "/repos/$owner/$repo/pulls/$number" | jq -r .head.sha)" != "$(git rev-parse HEAD)" ]; then
    # Forgejo rejects a push whose head the pull request already has, so only
    # push when there's something new to say.
    git push origin HEAD:refs/for/master -o "topic=$topic" -o force-push=true
fi

if ! api GET "/repos/$owner/$repo/issues/$number/labels" \
    | jq -e '.[] | select(.name == "agent")' >/dev/null; then
    label_id=$(api GET "/repos/$owner/$repo/labels" \
        | jq -r '.[] | select(.name == "agent") | .id')
    api POST "/repos/$owner/$repo/issues/$number/labels" \
        -d "$(jq -n --argjson id "$label_id" '{labels: [$id]}')" >/dev/null
fi

echo "$forgejo_url/$owner/$repo/pulls/$number"

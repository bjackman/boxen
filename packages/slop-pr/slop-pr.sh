
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

# AGit pull requests carry their topic in head.label, as "<owner>/<topic>";
# head.ref is always refs/pull/<n>/head and says nothing.
pr_number() {
    api GET "/repos/$owner/$repo/pulls?state=open" \
        | jq -r --arg label "$owner/$topic" \
            '.[] | select(.head.label == $label) | .number' \
        | head -1
}

push_args=(-o "topic=$topic" -o force-push=true)
if [ -z "$(pr_number)" ]; then
    # Only on creation: re-sending this on every update would clobber a title
    # edited in the web UI.
    title=${1:-$(git log --format=%s "origin/master..HEAD" | tail -1)}
    push_args+=(-o "title=$title")
fi

git push origin HEAD:refs/for/master "${push_args[@]}"

number=$(pr_number)
if [ -z "$number" ]; then
    echo "pushed, but found no pull request for topic $topic" >&2
    exit 1
fi

if ! api GET "/repos/$owner/$repo/issues/$number/labels" \
    | jq -e '.[] | select(.name == "agent")' >/dev/null; then
    label_id=$(api GET "/repos/$owner/$repo/labels" \
        | jq -r '.[] | select(.name == "agent") | .id')
    api POST "/repos/$owner/$repo/issues/$number/labels" \
        -d "$(jq -n --argjson id "$label_id" '{labels: [$id]}')" >/dev/null
fi

echo "$forgejo_url/$owner/$repo/pulls/$number"

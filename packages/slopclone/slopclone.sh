# Creates a local clone of a repo in ~/src/slop, adds that clone as a remote in
# the original repo. Then you can let an LLM agent go crazy in the clone without
# worrying that it will rewrite your history. Sole arg is src repo.

set -eu -o pipefail

SRC_REPO="$1"

SLOP_DIR=~/src/slop
DST_REPO="$SLOP_DIR/$(basename "$SRC_REPO")"

if [ -e "$DST_REPO" ]; then
    echo "$DST_REPO already exists"
    exit 1
fi

if git -C "$SRC_REPO" remote | grep -q "^slop$"; then
    echo "$SRC_REPO already has a remote called 'slop'"
    exit 1
fi

mkdir -p "$(dirname "$DST_REPO")"

pushd "$SLOP_DIR"
git clone "$SRC_REPO"/.git
popd >/dev/null

git -C "$SRC_REPO" remote add slop "$DST_REPO"/.git
// Package session maps a change - a repository and an AGit topic - onto the
// Claude Code session working on it. slop(1) derives the same values in shell,
// and the two must agree: if they don't, a review comment starts a fresh
// session instead of continuing the conversation that produced the change.
package session

import (
	"crypto/sha1"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
)

// The RFC 4122 URL namespace, matching `uuidgen --sha1 --namespace @url`.
var namespaceURL = [16]byte{
	0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1,
	0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
}

// ID is the session id for a change, as a UUIDv5 so that it needs no state to
// look up: the topic alone determines it.
func ID(repo, topic string) string {
	hash := sha1.New()
	hash.Write(namespaceURL[:])
	hash.Write([]byte(repo + ":" + topic))
	sum := hash.Sum(nil)[:16]
	sum[6] = (sum[6] & 0x0f) | 0x50
	sum[8] = (sum[8] & 0x3f) | 0x80

	encoded := hex.EncodeToString(sum)
	return strings.Join([]string{
		encoded[0:8], encoded[8:12], encoded[12:16], encoded[16:20], encoded[20:32],
	}, "-")
}

func Workspace(home, repo, topic string) string {
	return filepath.Join(home, "slop", repo, topic)
}

// Transcript is where Claude Code stores the conversation: under a directory
// named for the working directory, with the separators flattened.
func Transcript(home, workspace, id string) string {
	slug := strings.NewReplacer("/", "-", ".", "-").Replace(workspace)
	return filepath.Join(home, ".claude", "projects", slug, id+".jsonl")
}

// Started reports whether this session has any history to resume.
func Started(home, repo, topic string) bool {
	_, err := os.Stat(Transcript(home, Workspace(home, repo, topic), ID(repo, topic)))
	return err == nil
}

// TmuxName is the interactive session slop(1) runs in. Its existence means a
// human is driving, and the handler should keep its hands off the transcript.
func TmuxName(repo, topic string) string {
	return "slop-" + repo + "-" + topic
}

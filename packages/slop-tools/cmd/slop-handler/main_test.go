package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"testing"
)

func TestValidSignature(t *testing.T) {
	const secret = "hunter2"
	body := []byte(`{"action":"created"}`)

	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	good := hex.EncodeToString(mac.Sum(nil))

	for _, test := range []struct {
		name       string
		signatures []string
		want       bool
	}{
		{"forgejo header", []string{good, ""}, true},
		{"gitea header", []string{"", good}, true},
		{"wrong signature", []string{"0bad", ""}, false},
		// The interesting one: a delivery with no signature at all must not
		// pass, or the secret is decorative.
		{"absent", []string{"", ""}, false},
	} {
		if got := validSignature(secret, body, test.signatures...); got != test.want {
			t.Errorf("%s: validSignature() = %v, want %v", test.name, got, test.want)
		}
	}
}

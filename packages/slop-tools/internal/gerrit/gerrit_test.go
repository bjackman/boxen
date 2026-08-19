package gerrit

import "testing"

func TestStripMagic(t *testing.T) {
	// Gerrit prefixes JSON responses to break cross-site script inclusion.
	got := string(stripMagic([]byte(")]}'\n{\"a\": 1}")))
	if want := `{"a": 1}`; got != want {
		t.Errorf("stripMagic() = %q, want %q", got, want)
	}
	if got := string(stripMagic([]byte(`{"a": 1}`))); got != `{"a": 1}` {
		t.Errorf("stripMagic() altered an unprefixed body: %q", got)
	}
}

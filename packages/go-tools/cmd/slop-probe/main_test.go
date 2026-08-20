package main

import (
	"reflect"
	"testing"
)

func TestParseOptions(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []string
		want map[string]string
	}{
		{"separate value", []string{"--unit", "sshd.service"}, map[string]string{"unit": "sshd.service"}},
		{"joined value", []string{"--unit=sshd.service"}, map[string]string{"unit": "sshd.service"}},
		// The joined form is the only way to pass one of these, which is why
		// the usage message shows it.
		{"value starting with a dash", []string{"--since=-1h"}, map[string]string{"since": "-1h"}},
		{"switch", []string{"--reverse"}, map[string]string{"reverse": ""}},
		{"switch before an option", []string{"--reverse", "--lines", "5"}, map[string]string{"reverse": "", "lines": "5"}},
		{"switch at the end", []string{"--lines", "5", "--reverse"}, map[string]string{"lines": "5", "reverse": ""}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parseOptions(tc.args)
			if err != nil {
				t.Fatalf("parseOptions(%q) = %v", tc.args, err)
			}
			if !reflect.DeepEqual(got, tc.want) {
				t.Errorf("parseOptions(%q) = %v, want %v", tc.args, got, tc.want)
			}
		})
	}
}

func TestParseOptionsRejectsJunk(t *testing.T) {
	for _, args := range [][]string{
		{"sshd.service"},
		{"--"},
		{"--unit", "a", "--unit", "b"},
	} {
		if got, err := parseOptions(args); err == nil {
			t.Errorf("parseOptions(%q) = %v, want an error", args, got)
		}
	}
}

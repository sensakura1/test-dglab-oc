package config

import (
	"path/filepath"
	"testing"
)

func TestSafeDefaultsRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	want := SafeDefaults()
	if err := SaveFile(path, want); err != nil {
		t.Fatal(err)
	}
	got, err := LoadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if got.SchemaVersion != SchemaVersion || got.Trigger.DurationSeconds != 1 || got.Safety.HTTPLimitA != 30 {
		t.Fatalf("unexpected config: %#v", got)
	}
}

func TestRejectsUnsafeStrength(t *testing.T) {
	value := SafeDefaults()
	value.Trigger.StrengthA = Range{10, 201}
	if value.Validate() == nil {
		t.Fatal("expected unsafe strength to be rejected")
	}
}

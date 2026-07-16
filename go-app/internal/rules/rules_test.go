package rules

import "testing"

func TestClassifyPrioritizesBlacklist(t *testing.T) {
	got := Classify("Code | OC 设定 - 视频", []string{"Code | OC 设定 - 视频"}, []string{"Code | OC 设定 - 视频"})
	if got != Blacklist {
		t.Fatalf("got %q, want %q", got, Blacklist)
	}
}

func TestClassifyWhitelistAndUnknown(t *testing.T) {
	if got := Classify("Obsidian | OC 角色", []string{"obsidian | oc 角色"}, nil); got != Whitelist {
		t.Fatalf("got %q, want %q", got, Whitelist)
	}
	if got := Classify("unknown", nil, nil); got != Unknown {
		t.Fatalf("got %q, want %q", got, Unknown)
	}
}

func TestSplitSupportsChineseSeparators(t *testing.T) {
	got := Split("Code；Obsidian\nWord")
	if len(got) != 3 {
		t.Fatalf("got %#v", got)
	}
}

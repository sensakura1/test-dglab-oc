package session

import "testing"

func TestBlacklistTriggersOncePerEpisode(t *testing.T) {
	s := New(Limits{SessionMinutes: 45, LeaveSeconds: 3, IdleSeconds: 10})
	s.Start(Limits{SessionMinutes: 45})
	s.Connected = true
	if got, _ := s.ApplyWindow("video", "黑名单"); got != "黑名单直接触发" {
		t.Fatalf("got %q", got)
	}
	if got, _ := s.ApplyWindow("video", "黑名单"); got != "" {
		t.Fatalf("repeated trigger: %q", got)
	}
}

func TestLeaveAndIdleTimers(t *testing.T) {
	limits := Limits{SessionMinutes: 1, LeaveSeconds: 2, IdleSeconds: 3}
	s := New(limits)
	s.Start(limits)
	s.Connected = true
	s.ApplyWindow("other", "未匹配")
	if got := s.Tick(limits, 1); got != "" {
		t.Fatalf("early trigger: %q", got)
	}
	if got := s.Tick(limits, 2); got != "离开写作范围" {
		t.Fatalf("got %q", got)
	}
}

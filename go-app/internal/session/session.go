package session

import "time"

type WindowState string

const (
	Writing   WindowState = "writing"
	Left      WindowState = "left"
	Blacklist WindowState = "blacklist"
)

type State struct {
	Running            bool
	Paused             bool
	Locked             bool
	Connected          bool
	Window             WindowState
	SessionSeconds     int
	LeftSeconds        int
	DistractionSeconds int
	IdleSeconds        int
	IdleTriggerSent    bool
	AwayEpisodeActive  bool
	EpisodeTriggerSent bool
	StartedAt          time.Time
	LastWindow         string
}

type Limits struct {
	SessionMinutes int
	LeaveSeconds   int
	IdleSeconds    int
}

func New(limits Limits) *State {
	return &State{Window: Writing, SessionSeconds: limits.SessionMinutes * 60}
}

func (s *State) Start(limits Limits) {
	s.Running = true
	s.Paused = false
	s.Locked = false
	s.SessionSeconds = limits.SessionMinutes * 60
	s.LeftSeconds = 0
	s.DistractionSeconds = 0
	s.IdleSeconds = 0
	s.IdleTriggerSent = false
	s.AwayEpisodeActive = false
	s.EpisodeTriggerSent = false
	s.StartedAt = time.Now()
}

func (s *State) End() {
	s.Running = false
	s.Paused = false
	s.LeftSeconds = 0
	s.DistractionSeconds = 0
	s.IdleSeconds = 0
	s.AwayEpisodeActive = false
	s.EpisodeTriggerSent = false
}

func (s *State) TogglePause() {
	if s.Running {
		s.Paused = !s.Paused
	}
}

func (s *State) EmergencyLock() {
	s.Locked = true
	s.Running = false
	s.Paused = false
}

func (s *State) StatusText() string {
	if s.Locked {
		return "急停锁定"
	}
	if !s.Running {
		return "未开始"
	}
	if s.Paused {
		return "已暂停"
	}
	switch s.Window {
	case Writing:
		return "写作中"
	case Left:
		return "离开中"
	case Blacklist:
		return "黑名单命中"
	default:
		return "未知"
	}
}

func (s *State) ApplyWindow(display, classification string) (trigger string, returnedToWhitelist bool) {
	changed := s.LastWindow != display
	if changed {
		s.LastWindow = display
	}
	switch classification {
	case "黑名单":
		s.Window = Blacklist
		s.LeftSeconds = 0
		if !s.AwayEpisodeActive {
			s.AwayEpisodeActive = true
			s.EpisodeTriggerSent = false
		}
		if s.Running && !s.Paused && !s.Locked && s.Connected && !s.EpisodeTriggerSent {
			s.EpisodeTriggerSent = true
			return "黑名单直接触发", false
		}
	case "白名单":
		s.Window = Writing
		s.LeftSeconds = 0
		s.DistractionSeconds = 0
		s.AwayEpisodeActive = false
		s.EpisodeTriggerSent = false
		return "", true
	default:
		s.Window = Left
		if !s.AwayEpisodeActive {
			s.AwayEpisodeActive = true
			s.EpisodeTriggerSent = false
		}
	}
	return "", false
}

func (s *State) Tick(limits Limits, systemIdleSeconds int) string {
	if !s.Running || s.Paused || s.Locked {
		return ""
	}
	if s.SessionSeconds > 0 {
		s.SessionSeconds--
	}
	if systemIdleSeconds < s.IdleSeconds {
		s.IdleTriggerSent = false
	}
	s.IdleSeconds = systemIdleSeconds
	switch s.Window {
	case Writing:
		s.LeftSeconds = 0
	case Left:
		s.LeftSeconds++
	case Blacklist:
		s.LeftSeconds = 0
	}
	if s.AwayEpisodeActive && !s.EpisodeTriggerSent && s.Window == Left && s.LeftSeconds >= limits.LeaveSeconds && s.Connected {
		s.EpisodeTriggerSent = true
		return "离开写作范围"
	}
	if !s.IdleTriggerSent && s.IdleSeconds >= limits.IdleSeconds && s.Connected {
		s.IdleTriggerSent = true
		return "长时间无输入"
	}
	if s.SessionSeconds == 0 {
		s.Running = false
		return "专注周期结束"
	}
	return ""
}

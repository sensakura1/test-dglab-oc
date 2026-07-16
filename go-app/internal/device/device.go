package device

import (
	"context"
	"fmt"
	"math/rand"
	"sync"
	"time"

	appconfig "ocwritingfocus/goapp/internal/config"
)

type Profile struct {
	AEnabled           bool
	BEnabled           bool
	AStrength          int
	BStrength          int
	Channel            string
	Duration           time.Duration
	MaxContinuous      time.Duration
	Cooldown           time.Duration
	HoldUntilWhitelist bool
	RestartOnRepeat    bool
	Waveform           string
	WavePeriodMs       int
	WaveIntensity      int
}

type Status struct {
	Connected bool
	Text      string
	Source    string
	ActualA   int
	ActualB   int
	Known     bool
	LimitA    int
	LimitB    int
	HasLimits bool
}

type Adapter interface {
	Connect(context.Context) error
	Disconnect(context.Context) error
	Activate(context.Context, Profile) error
	Stop(context.Context) error
	Status() Status
}

type Manager struct {
	mu      sync.Mutex
	adapter Adapter
}

func (m *Manager) Use(adapter Adapter) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.adapter = adapter
}

func (m *Manager) Adapter() Adapter {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.adapter
}

func NewProfile(c appconfig.Config) Profile {
	a := randomRange(c.Trigger.StrengthA)
	b := randomRange(c.Trigger.StrengthB)
	switch c.Trigger.Channel {
	case "A":
		b = 0
	case "B":
		a = 0
	}
	return Profile{
		AEnabled: c.Trigger.Channel != "B", BEnabled: c.Trigger.Channel != "A",
		AStrength: a, BStrength: b, Channel: c.Trigger.Channel,
		Duration:           time.Duration(c.Trigger.DurationSeconds) * time.Second,
		MaxContinuous:      time.Duration(c.Trigger.MaxContinuousSeconds) * time.Second,
		Cooldown:           time.Duration(c.Trigger.CooldownSeconds) * time.Second,
		HoldUntilWhitelist: c.Trigger.OutputMode == "untilWhitelist",
		RestartOnRepeat:    c.Trigger.OverlapMode == "restart",
		Waveform:           c.Trigger.Waveform, WavePeriodMs: c.Trigger.WavePeriodMs, WaveIntensity: c.Trigger.WaveIntensity,
	}
}

func Limit(profile Profile, limitA, limitB int) Profile {
	profile.AStrength = min(profile.AStrength, limitA)
	profile.BStrength = min(profile.BStrength, limitB)
	return profile
}

func EnsureLimits(status Status) error {
	if !status.HasLimits {
		return fmt.Errorf("尚未获得设备 A/B 安全上限，已禁止输出")
	}
	return nil
}

func randomRange(value appconfig.Range) int {
	if value[1] <= value[0] {
		return value[0]
	}
	return value[0] + rand.Intn(value[1]-value[0]+1)
}

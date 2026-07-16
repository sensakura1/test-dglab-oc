package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

const SchemaVersion = 2

type Range [2]int

type Config struct {
	SchemaVersion int           `json:"schemaVersion"`
	Focus         FocusConfig   `json:"focus"`
	Trigger       TriggerConfig `json:"trigger"`
	Device        DeviceConfig  `json:"device"`
	Safety        SafetyConfig  `json:"safety"`
	Scope         ScopeConfig   `json:"scope"`
}

type FocusConfig struct {
	SessionMinutes int `json:"sessionMinutes"`
	LeaveSeconds   int `json:"leaveSeconds"`
	IdleSeconds    int `json:"idleSeconds"`
}

type TriggerConfig struct {
	OutputMode           string `json:"outputMode"`
	OverlapMode          string `json:"overlapMode"`
	Channel              string `json:"channel"`
	StrengthA            Range  `json:"strengthA"`
	StrengthB            Range  `json:"strengthB"`
	Waveform             string `json:"waveform"`
	WavePeriodMs         int    `json:"wavePeriodMs"`
	WaveIntensity        int    `json:"waveIntensity"`
	DurationSeconds      int    `json:"durationSeconds"`
	MaxContinuousSeconds int    `json:"maxContinuousSeconds"`
	CooldownSeconds      int    `json:"cooldownSeconds"`
}

type DeviceConfig struct {
	Mode         string       `json:"mode"`
	HTTPEndpoint string       `json:"httpEndpoint"`
	BLEAddress   string       `json:"bleAddress"`
	Socket       SocketConfig `json:"socket"`
}

type SocketConfig struct {
	Mode         string `json:"mode"`
	LocalHost    string `json:"localHost"`
	LocalPort    int    `json:"localPort"`
	RemoteServer string `json:"remoteServer"`
}

type SafetyConfig struct {
	HTTPLimitA        int `json:"httpLimitA"`
	HTTPLimitB        int `json:"httpLimitB"`
	SoftLimitA        int `json:"softLimitA"`
	SoftLimitB        int `json:"softLimitB"`
	FrequencyBalanceA int `json:"frequencyBalanceA"`
	FrequencyBalanceB int `json:"frequencyBalanceB"`
	StrengthBalanceA  int `json:"strengthBalanceA"`
	StrengthBalanceB  int `json:"strengthBalanceB"`
}

type ScopeConfig struct {
	Whitelist []string `json:"whitelist"`
	Blacklist []string `json:"blacklist"`
}

func SafeDefaults() Config {
	return Config{
		SchemaVersion: SchemaVersion,
		Focus:         FocusConfig{SessionMinutes: 45, LeaveSeconds: 300, IdleSeconds: 600},
		Trigger: TriggerConfig{
			OutputMode: "fixedDuration", OverlapMode: "restart", Channel: "both",
			StrengthA: Range{10, 20}, StrengthB: Range{10, 20}, Waveform: "constant",
			WavePeriodMs: 30, WaveIntensity: 20, DurationSeconds: 1,
			MaxContinuousSeconds: 10, CooldownSeconds: 60,
		},
		Device: DeviceConfig{
			Mode: "http", HTTPEndpoint: "http://127.0.0.1:8080",
			Socket: SocketConfig{Mode: "local", LocalHost: PreferredLocalIPv4(), LocalPort: 5678, RemoteServer: "ws://192.168.1.100:5678"},
		},
		Safety: SafetyConfig{HTTPLimitA: 30, HTTPLimitB: 30, SoftLimitA: 30, SoftLimitB: 30},
		Scope:  ScopeConfig{Whitelist: []string{}, Blacklist: []string{}},
	}
}

func Path() string {
	root, err := os.UserConfigDir()
	if err != nil {
		return "go-config.json"
	}
	return filepath.Join(root, "OCWritingFocus", "go-config.json")
}

func Load() (Config, error) {
	return LoadFile(Path())
}

func LoadFile(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return SafeDefaults(), nil
	}
	if err != nil {
		return SafeDefaults(), err
	}
	var value Config
	if err := json.Unmarshal(data, &value); err != nil {
		return SafeDefaults(), fmt.Errorf("配置 JSON 无效: %w", err)
	}
	if err := value.Validate(); err != nil {
		return SafeDefaults(), err
	}
	return value, nil
}

func Save(value Config) error {
	return SaveFile(Path(), value)
}

func SaveFile(path string, value Config) error {
	value.SchemaVersion = SchemaVersion
	if err := value.Validate(); err != nil {
		return err
	}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}

func (c Config) Validate() error {
	if c.SchemaVersion != SchemaVersion {
		return fmt.Errorf("不支持的配置版本: %d", c.SchemaVersion)
	}
	if !between(c.Focus.SessionMinutes, 1, 10080) || !between(c.Focus.LeaveSeconds, 1, 86400) || !between(c.Focus.IdleSeconds, 1, 86400) {
		return errors.New("专注时间配置超出安全范围")
	}
	if !oneOf(c.Trigger.OutputMode, "untilWhitelist", "fixedDuration") || !oneOf(c.Trigger.OverlapMode, "restart", "extend") || !oneOf(c.Trigger.Channel, "both", "A", "B") {
		return errors.New("触发模式配置无效")
	}
	if !validRange(c.Trigger.StrengthA, 0, 200) || !validRange(c.Trigger.StrengthB, 0, 200) {
		return errors.New("A/B 强度范围无效")
	}
	if !oneOf(c.Trigger.Waveform, "constant", "pulse", "ramp", "heartbeat") || !between(c.Trigger.WavePeriodMs, 10, 1000) || !between(c.Trigger.WaveIntensity, 0, 100) {
		return errors.New("波形配置无效")
	}
	if !between(c.Trigger.DurationSeconds, 1, 30) || !between(c.Trigger.MaxContinuousSeconds, 1, 30) || !between(c.Trigger.CooldownSeconds, 5, 3600) {
		return errors.New("输出持续或冷却配置无效")
	}
	if !oneOf(c.Device.Mode, "http", "ble", "socket") || !oneOf(c.Device.Socket.Mode, "local", "remote") || !between(c.Device.Socket.LocalPort, 1, 65535) {
		return errors.New("设备连接配置无效")
	}
	for _, value := range []int{c.Safety.HTTPLimitA, c.Safety.HTTPLimitB, c.Safety.SoftLimitA, c.Safety.SoftLimitB} {
		if !between(value, 0, 200) {
			return errors.New("强度安全上限无效")
		}
	}
	for _, value := range []int{c.Safety.FrequencyBalanceA, c.Safety.FrequencyBalanceB, c.Safety.StrengthBalanceA, c.Safety.StrengthBalanceB} {
		if !between(value, 0, 255) {
			return errors.New("BF 平衡参数无效")
		}
	}
	return nil
}

func between(value, min, max int) bool { return value >= min && value <= max }

func validRange(value Range, min, max int) bool {
	return between(value[0], min, max) && between(value[1], min, max) && value[0] <= value[1]
}

func oneOf(value string, values ...string) bool {
	for _, candidate := range values {
		if value == candidate {
			return true
		}
	}
	return false
}

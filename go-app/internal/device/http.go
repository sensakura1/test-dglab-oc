package device

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"
)

type HTTPAdapter struct {
	mu       sync.Mutex
	Endpoint string
	LimitA   int
	LimitB   int
	client   *http.Client
	status   Status
}

func NewHTTP(endpoint string, limitA, limitB int) *HTTPAdapter {
	return &HTTPAdapter{
		Endpoint: endpoint, LimitA: limitA, LimitB: limitB,
		client: &http.Client{Timeout: 5 * time.Second},
		status: Status{Text: "真实桥接未连接", Source: "未连接", LimitA: limitA, LimitB: limitB, HasLimits: true},
	}
}

func (a *HTTPAdapter) Connect(ctx context.Context) error {
	endpoint, err := a.actionURL("status")
	if err != nil {
		return err
	}
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	response, err := a.client.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("HTTP 状态检查失败: %s", response.Status)
	}
	a.mu.Lock()
	a.status.Connected = true
	a.status.Text = "真实桥接已连接"
	a.status.Source = "HTTP 桥接"
	a.mu.Unlock()
	return nil
}

func (a *HTTPAdapter) Disconnect(ctx context.Context) error {
	_ = a.Stop(ctx)
	a.mu.Lock()
	a.status.Connected = false
	a.status.Known = false
	a.status.Text = "真实桥接未连接"
	a.status.Source = "设备已断开"
	a.mu.Unlock()
	return nil
}

func (a *HTTPAdapter) Activate(ctx context.Context, profile Profile) error {
	duration := profile.Duration
	if profile.HoldUntilWhitelist {
		duration = profile.MaxContinuous
	}
	body := map[string]any{
		"action": "activate", "intensity": max(profile.AStrength, profile.BStrength),
		"intensityA": profile.AStrength, "intensityB": profile.BStrength,
		"durationMs": duration.Milliseconds(), "channel": profile.Channel,
		"pattern": profile.Waveform, "pulseId": profile.Waveform,
		"overrides": profile.RestartOnRepeat, "wavePeriodMs": profile.WavePeriodMs,
		"waveIntensity": profile.WaveIntensity, "softLimitA": a.LimitA, "softLimitB": a.LimitB,
	}
	if err := a.post(ctx, "activate", body); err != nil {
		return err
	}
	a.mu.Lock()
	a.status.ActualA, a.status.ActualB, a.status.Known = profile.AStrength, profile.BStrength, true
	a.status.Source = "HTTP 桥接已确认接收"
	a.mu.Unlock()
	return nil
}

func (a *HTTPAdapter) Stop(ctx context.Context) error {
	err := a.post(ctx, "stop", map[string]any{"action": "stop"})
	if err == nil {
		a.mu.Lock()
		a.status.ActualA, a.status.ActualB, a.status.Known = 0, 0, true
		a.status.Source = "HTTP 桥接已确认接收"
		a.mu.Unlock()
	}
	return err
}

func (a *HTTPAdapter) Status() Status {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.status
}

func (a *HTTPAdapter) post(ctx context.Context, action string, body any) error {
	endpoint, err := a.actionURL(action)
	if err != nil {
		return err
	}
	data, _ := json.Marshal(body)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(data))
	req.Header.Set("Content-Type", "application/json")
	response, err := a.client.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("HTTP %s 失败: %s", action, response.Status)
	}
	return nil
}

func (a *HTTPAdapter) actionURL(action string) (string, error) {
	value, err := SecureEndpoint(a.Endpoint, "http")
	if err != nil {
		return "", err
	}
	base := strings.TrimRight(value.String(), "/")
	for _, suffix := range []string{"/activate", "/stop", "/status"} {
		if strings.HasSuffix(base, suffix) {
			base = strings.TrimSuffix(base, suffix)
			break
		}
	}
	return base + "/" + action, nil
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

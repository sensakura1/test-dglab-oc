package device

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestHTTPAdapterConnectActivateAndStop(t *testing.T) {
	actions := make(chan map[string]any, 2)
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path == "/status" {
			response.WriteHeader(http.StatusOK)
			return
		}
		var body map[string]any
		if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		actions <- body
		response.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	adapter := NewHTTP(server.URL, 30, 40)
	if err := adapter.Connect(context.Background()); err != nil {
		t.Fatal(err)
	}
	profile := Profile{AEnabled: true, BEnabled: true, AStrength: 20, BStrength: 25, Channel: "both", Duration: time.Second, Waveform: "constant", WavePeriodMs: 30, WaveIntensity: 20}
	if err := adapter.Activate(context.Background(), profile); err != nil {
		t.Fatal(err)
	}
	activate := <-actions
	if activate["action"] != "activate" || int(activate["intensityA"].(float64)) != 20 || int(activate["softLimitB"].(float64)) != 40 {
		t.Fatalf("unexpected activate body: %#v", activate)
	}
	if err := adapter.Stop(context.Background()); err != nil {
		t.Fatal(err)
	}
	if stop := <-actions; stop["action"] != "stop" {
		t.Fatalf("unexpected stop body: %#v", stop)
	}
}

func TestBLEB0StopAndActivePackets(t *testing.T) {
	stop := b0Packet(Profile{}, true)
	if len(stop) != 20 || stop[0] != 0xB0 || stop[1] != 0x0F || stop[2] != 0 || stop[3] != 0 {
		t.Fatalf("invalid stop packet: %#v", stop)
	}
	active := b0Packet(Profile{AEnabled: true, BEnabled: true, AStrength: 17, BStrength: 23, Waveform: "pulse", WavePeriodMs: 30, WaveIntensity: 35}, false)
	if len(active) != 20 || active[1] != 0x0F || active[2] != 17 || active[3] != 23 || active[9] != 0 {
		t.Fatalf("invalid active packet: %#v", active)
	}
}

func TestSocketStrengthReportProvidesLimits(t *testing.T) {
	adapter := NewSocket("local", "127.0.0.1", 5678, "")
	adapter.applyStrength("strength-17+23+30+40")
	status := adapter.Status()
	if !status.HasLimits || status.ActualA != 17 || status.ActualB != 23 || status.LimitA != 30 || status.LimitB != 40 {
		t.Fatalf("unexpected socket status: %#v", status)
	}
}

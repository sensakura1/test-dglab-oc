package device

import "testing"

func TestSecureEndpoint(t *testing.T) {
	for _, value := range []string{"http://127.0.0.1:8080", "ws://192.168.1.20:5678", "https://device.example.com", "wss://socket.example.com"} {
		kind := "http"
		if value[0] == 'w' {
			kind = "socket"
		}
		if _, err := SecureEndpoint(value, kind); err != nil {
			t.Fatalf("%s: %v", value, err)
		}
	}
	for _, value := range []string{"http://example.com", "ws://8.8.8.8:5678", "http://user:pass@127.0.0.1:8080"} {
		kind := "http"
		if value[0] == 'w' {
			kind = "socket"
		}
		if _, err := SecureEndpoint(value, kind); err == nil {
			t.Fatalf("expected %s rejected", value)
		}
	}
}

package device

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var strengthMessage = regexp.MustCompile(`^strength-(\d{1,3})\+(\d{1,3})\+(\d{1,3})\+(\d{1,3})$`)

type SocketAdapter struct {
	mu           sync.Mutex
	Mode         string
	LocalHost    string
	LocalPort    int
	RemoteServer string
	conn         *websocket.Conn
	server       *http.Server
	clientID     string
	targetID     string
	serverURI    string
	status       Status
	watchdog     *time.Timer
	closed       chan struct{}
}

func NewSocket(mode, localHost string, localPort int, remoteServer string) *SocketAdapter {
	return &SocketAdapter{
		Mode: mode, LocalHost: localHost, LocalPort: localPort, RemoteServer: remoteServer,
		status: Status{Text: "等待 App 绑定", Source: "Socket 未连接"}, closed: make(chan struct{}),
	}
}

func (a *SocketAdapter) Connect(ctx context.Context) error {
	if a.Mode == "local" {
		return a.startLocal()
	}
	return a.connectRemote(ctx)
}

func (a *SocketAdapter) startLocal() error {
	uri, err := SecureEndpoint(fmt.Sprintf("ws://%s:%d", a.LocalHost, a.LocalPort), "socket")
	if err != nil {
		return err
	}
	a.clientID = randomID()
	a.serverURI = strings.TrimRight(uri.String(), "/")
	upgrader := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		path := strings.Trim(r.URL.Path, "/")
		if path != "" && !strings.EqualFold(path, a.clientID) {
			http.Error(w, "invalid client id", http.StatusNotFound)
			return
		}
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		a.setConnection(conn)
	})
	listener, err := net.Listen("tcp", net.JoinHostPort(a.LocalHost, strconv.Itoa(a.LocalPort)))
	if err != nil {
		return err
	}
	a.server = &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	a.mu.Lock()
	a.status.Text = "本地服务器已启动，等待 App 绑定"
	a.status.Source = "Socket 本地服务器"
	a.mu.Unlock()
	go func() { _ = a.server.Serve(listener) }()
	return nil
}

func (a *SocketAdapter) connectRemote(ctx context.Context) error {
	uri, err := SecureEndpoint(a.RemoteServer, "socket")
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	conn, _, err := websocket.DefaultDialer.DialContext(ctx, uri.String(), nil)
	if err != nil {
		return err
	}
	a.serverURI = strings.TrimRight(uri.String(), "/")
	a.mu.Lock()
	a.conn = conn
	a.status.Text = "服务器已连接，等待注册与 App 绑定"
	a.status.Source = "Socket 外部服务器"
	a.mu.Unlock()
	go a.readLoop(conn)
	return nil
}

func (a *SocketAdapter) setConnection(conn *websocket.Conn) {
	a.mu.Lock()
	if a.conn != nil {
		_ = a.conn.Close()
	}
	a.conn = conn
	if a.targetID == "" {
		a.targetID = randomID()
	}
	a.status.Connected = true
	a.status.Text = "App 已绑定，等待强度上限"
	a.status.Source = "Socket App"
	a.mu.Unlock()
	go a.readLoop(conn)
}

func (a *SocketAdapter) readLoop(conn *websocket.Conn) {
	for {
		_, data, err := conn.ReadMessage()
		if err != nil {
			a.mu.Lock()
			if a.conn == conn {
				a.status.Connected = false
				a.status.Text = "App 已断开，请重新绑定"
				a.status.HasLimits = false
			}
			a.mu.Unlock()
			return
		}
		var message struct {
			Type, ClientID, TargetID, Message string
		}
		if json.Unmarshal(data, &message) != nil {
			continue
		}
		switch message.Type {
		case "bind":
			if message.Message == "targetId" {
				a.mu.Lock()
				a.clientID = message.ClientID
				a.status.Text = "服务器已注册，等待 App 绑定"
				a.mu.Unlock()
			} else if message.Message == "200" {
				a.mu.Lock()
				a.targetID = message.TargetID
				a.status.Connected = true
				a.status.Text = "App 已绑定，等待强度上限"
				a.mu.Unlock()
			}
		case "msg":
			a.applyStrength(message.Message)
		case "break":
			a.mu.Lock()
			a.status.Connected = false
			a.status.HasLimits = false
			a.targetID = ""
			a.status.Text = "App 已断开，请重新绑定"
			a.mu.Unlock()
		}
	}
}

func (a *SocketAdapter) applyStrength(body string) {
	match := strengthMessage.FindStringSubmatch(body)
	if len(match) != 5 {
		return
	}
	values := make([]int, 4)
	for index := range values {
		values[index], _ = strconv.Atoi(match[index+1])
		values[index] = min(200, max(0, values[index]))
	}
	a.mu.Lock()
	a.status.ActualA, a.status.ActualB = values[0], values[1]
	a.status.LimitA, a.status.LimitB = values[2], values[3]
	a.status.Known, a.status.HasLimits = true, true
	a.status.Source = "Socket App 实时回报"
	a.status.Text = fmt.Sprintf("当前 A=%d / 上限 %d；B=%d / 上限 %d", values[0], values[2], values[1], values[3])
	a.mu.Unlock()
}

func (a *SocketAdapter) Activate(ctx context.Context, profile Profile) error {
	status := a.Status()
	if err := EnsureLimits(status); err != nil {
		return err
	}
	profile = Limit(profile, status.LimitA, status.LimitB)
	commands := []string{"clear-1", "clear-2", fmt.Sprintf("strength-1+2+%d", profile.AStrength), fmt.Sprintf("strength-2+2+%d", profile.BStrength)}
	for _, command := range commands {
		if err := a.send(command); err != nil {
			return err
		}
	}
	duration := profile.Duration
	if profile.HoldUntilWhitelist {
		duration = profile.MaxContinuous
	}
	a.armWatchdog(duration)
	a.mu.Lock()
	a.status.ActualA, a.status.ActualB, a.status.Known = profile.AStrength, profile.BStrength, true
	a.status.Source = "Socket 已下发，等待 App 回报"
	a.mu.Unlock()
	return nil
}

func (a *SocketAdapter) Stop(ctx context.Context) error {
	commands := []string{"strength-1+2+0", "strength-2+2+0", "clear-1", "clear-2"}
	var last error
	for round := 0; round < 3; round++ {
		for _, command := range commands {
			if err := a.send(command); err != nil {
				last = err
			}
		}
		if last == nil {
			break
		}
	}
	a.mu.Lock()
	if a.watchdog != nil {
		a.watchdog.Stop()
	}
	a.status.ActualA, a.status.ActualB, a.status.Known = 0, 0, true
	a.status.Source = "Socket 停止命令已下发"
	a.mu.Unlock()
	return last
}

func (a *SocketAdapter) Disconnect(ctx context.Context) error {
	_ = a.Stop(ctx)
	a.mu.Lock()
	if a.conn != nil {
		_ = a.conn.Close()
		a.conn = nil
	}
	if a.server != nil {
		_ = a.server.Shutdown(ctx)
		a.server = nil
	}
	a.status = Status{Text: "等待 App 绑定", Source: "Socket 已断开"}
	a.mu.Unlock()
	return nil
}

func (a *SocketAdapter) Status() Status {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.status
}

func (a *SocketAdapter) QRText() string {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.serverURI == "" || a.clientID == "" {
		return ""
	}
	return a.serverURI + "/" + a.clientID
}

func (a *SocketAdapter) send(command string) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.conn == nil || !a.status.Connected || a.clientID == "" || a.targetID == "" {
		return fmt.Errorf("Socket App 尚未完成绑定")
	}
	payload := map[string]string{"type": "msg", "clientId": a.clientID, "targetId": a.targetID, "message": command}
	a.conn.SetWriteDeadline(time.Now().Add(time.Second))
	return a.conn.WriteJSON(payload)
}

func (a *SocketAdapter) armWatchdog(duration time.Duration) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.watchdog != nil {
		a.watchdog.Stop()
	}
	a.watchdog = time.AfterFunc(duration, func() { _ = a.Stop(context.Background()) })
}

func randomID() string {
	buffer := make([]byte, 16)
	_, _ = rand.Read(buffer)
	return hex.EncodeToString(buffer)
}

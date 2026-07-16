//go:build windows

package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/lxn/walk"
	qrcode "github.com/skip2/go-qrcode"

	appconfig "ocwritingfocus/goapp/internal/config"
	"ocwritingfocus/goapp/internal/device"
	"ocwritingfocus/goapp/internal/monitor"
	"ocwritingfocus/goapp/internal/rules"
	"ocwritingfocus/goapp/internal/session"
)

type application struct {
	mainWindow    *walk.MainWindow
	pages         map[string]*walk.Composite
	dashboardView *walk.Composite
	scopeView     *walk.Composite
	triggerView   *walk.Composite
	deviceView    *walk.Composite
	logsView      *walk.Composite
	pageTitle     *walk.Label
	pageEye       *walk.Label

	currentWindow  *walk.LineEdit
	currentMatch   *walk.Label
	statusValue    *walk.Label
	sessionValue   *walk.Label
	leftValue      *walk.Label
	distractValue  *walk.Label
	idleValue      *walk.Label
	strengthValue  *walk.Label
	strengthSource *walk.Label
	deviceBadge    *walk.Label
	lockBadge      *walk.Label

	windowPicker *walk.ComboBox
	whitelist    *walk.ListBox
	blacklist    *walk.ListBox
	logList      *walk.ListBox

	focusMinutes  *walk.LineEdit
	leaveSeconds  *walk.LineEdit
	idleSeconds   *walk.LineEdit
	outputMode    *walk.ComboBox
	overlapMode   *walk.ComboBox
	channelMode   *walk.ComboBox
	strengthA     *walk.LineEdit
	strengthB     *walk.LineEdit
	waveform      *walk.ComboBox
	wavePeriod    *walk.LineEdit
	waveIntensity *walk.LineEdit
	duration      *walk.LineEdit
	maxContinuous *walk.LineEdit
	cooldown      *walk.LineEdit

	deviceMode        *walk.ComboBox
	httpPanel         *walk.Composite
	blePanel          *walk.Composite
	socketPanel       *walk.Composite
	httpEndpoint      *walk.LineEdit
	httpLimitA        *walk.LineEdit
	httpLimitB        *walk.LineEdit
	bleAddress        *walk.LineEdit
	softLimitA        *walk.LineEdit
	softLimitB        *walk.LineEdit
	freqBalanceA      *walk.LineEdit
	freqBalanceB      *walk.LineEdit
	strengthBalanceA  *walk.LineEdit
	strengthBalanceB  *walk.LineEdit
	socketMode        *walk.ComboBox
	localHost         *walk.LineEdit
	localPort         *walk.LineEdit
	remoteServer      *walk.LineEdit
	socketStatus      *walk.Label
	socketLimits      *walk.Label
	socketAddress     *walk.LineEdit
	socketQRText      *walk.LineEdit
	socketQRImage     *walk.ImageView
	deviceValue       *walk.Label
	connectButton     *walk.PushButton
	applySafetyButton *walk.PushButton
	unlockButton      *walk.PushButton

	channelWindow    *walk.MainWindow
	channelStrength  *walk.Label
	channelDuration  *walk.Label
	channelRemaining *walk.Label
	channelSource    *walk.Label
	windowMonitor    *walk.MainWindow
	floatingWindow   *walk.Label
	floatingMatch    *walk.Label

	config        appconfig.Config
	session       *session.State
	devices       device.Manager
	logs          []string
	windowItems   []string
	mu            sync.Mutex
	timerStop     chan struct{}
	outputActive  bool
	outputProfile device.Profile
	outputEnd     time.Time
}

func main() {
	value, loadErr := appconfig.Load()
	app := &application{config: value, pages: map[string]*walk.Composite{}, timerStop: make(chan struct{})}
	app.session = session.New(app.limits())
	if err := app.createMainWindow(); err != nil {
		walk.MsgBox(nil, "Go 正式版启动失败", err.Error(), walk.MsgBoxIconError)
		return
	}
	if loadErr != nil {
		app.addLog("配置加载失败，已使用安全默认值：" + loadErr.Error())
	}
	app.applyConfigToUI()
	app.showPage("dashboard")
	app.refreshWindowPicker()
	app.refreshWindow()
	app.addLog("Go 桌面应用已启动")
	go app.runTimers()
	app.mainWindow.Closing().Attach(app.onClosing)
	app.mainWindow.Run()
}

func (a *application) runTimers() {
	ticker := time.NewTicker(time.Second)
	fast := time.NewTicker(200 * time.Millisecond)
	defer ticker.Stop()
	defer fast.Stop()
	for {
		select {
		case <-ticker.C:
			a.mainWindow.Synchronize(a.tick)
		case <-fast.C:
			a.mainWindow.Synchronize(a.updateFloatingMonitors)
		case <-a.timerStop:
			return
		}
	}
}

func (a *application) tick() {
	display, classification := a.refreshWindow()
	a.session.Connected = a.currentDeviceStatus().Connected
	reason, returned := a.session.ApplyWindow(display, classification)
	if returned && a.outputActive && a.outputProfile.HoldUntilWhitelist {
		a.stopDevice("返回白名单，输出已停止")
	}
	if reason != "" {
		a.trigger(reason)
	}
	idle := int(monitor.IdleMilliseconds() / 1000)
	if !a.session.StartedAt.IsZero() {
		age := int(time.Since(a.session.StartedAt).Seconds())
		if idle > age {
			idle = age
		}
	}
	if reason := a.session.Tick(a.limits(), idle); reason != "" {
		a.trigger(reason)
	}
	if a.outputActive && !time.Now().Before(a.outputEnd) {
		a.stopDevice("已达到输出持续上限")
	}
	a.updateView()
}

func (a *application) refreshWindow() (string, string) {
	info := monitor.Foreground()
	display := info.Display()
	classification := string(rules.Classify(display, a.config.Scope.Whitelist, a.config.Scope.Blacklist))
	a.currentWindow.SetText(display)
	a.currentMatch.SetText(classification)
	if a.floatingWindow != nil {
		a.floatingWindow.SetText(display)
		a.floatingMatch.SetText("范围判定：" + classification + "  /  每 1 秒刷新")
	}
	return display, classification
}

func (a *application) startFocus() {
	if err := a.captureConfig(); err != nil {
		a.showError("配置无效", err)
		return
	}
	a.session.Start(a.limits())
	a.addLog("专注周期已开始")
	a.updateView()
}

func (a *application) togglePause() {
	a.session.TogglePause()
	a.addLog(map[bool]string{true: "专注已暂停", false: "专注已恢复"}[a.session.Paused])
	a.updateView()
}

func (a *application) endFocus() {
	if a.outputActive {
		a.stopDevice("专注结束，输出已停止")
	}
	a.session.End()
	a.addLog("专注周期已结束")
	a.updateView()
}

func (a *application) emergencyStop() {
	a.stopDevice("急停已执行，设备输出停止")
	a.session.EmergencyLock()
	a.addLog("急停已执行，进入安全锁定")
	a.updateView()
}

func (a *application) unlock() {
	a.session.Locked = false
	a.addLog("安全锁定已解除")
	a.updateView()
}

func (a *application) trigger(reason string) {
	if a.session.Locked {
		a.addLog("触发被拦截：安全锁定")
		return
	}
	adapter := a.devices.Adapter()
	if adapter == nil || !adapter.Status().Connected {
		a.addLog("触发被拦截：设备未连接")
		return
	}
	profile := device.NewProfile(a.config)
	if reason != "黑名单直接触发" && reason != "离开写作范围" && reason != "冷却结束仍未返回白名单" {
		profile.HoldUntilWhitelist = false
	}
	status := adapter.Status()
	if err := device.EnsureLimits(status); err != nil {
		a.addLog("触发被拦截：" + err.Error())
		return
	}
	profile = device.Limit(profile, status.LimitA, status.LimitB)
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	defer cancel()
	if err := adapter.Activate(ctx, profile); err != nil {
		a.addLog("设备触发失败：" + err.Error())
		return
	}
	a.outputActive = true
	a.outputProfile = profile
	duration := profile.Duration
	if profile.HoldUntilWhitelist {
		duration = profile.MaxContinuous
	}
	a.outputEnd = time.Now().Add(duration)
	a.addLog(fmt.Sprintf("%s：通道 %s，A=%d B=%d，波形 %s，%s", reason, profile.Channel, profile.AStrength, profile.BStrength, profile.Waveform, duration))
	a.updateView()
}

func (a *application) connectDevice() {
	if err := a.captureConfig(); err != nil {
		a.showError("配置无效", err)
		return
	}
	var adapter device.Adapter
	switch a.config.Device.Mode {
	case "ble":
		adapter = device.NewBLE(a.config.Device.BLEAddress, a.config.Safety)
	case "socket":
		adapter = device.NewSocket(a.config.Device.Socket.Mode, a.config.Device.Socket.LocalHost, a.config.Device.Socket.LocalPort, a.config.Device.Socket.RemoteServer)
	default:
		adapter = device.NewHTTP(a.config.Device.HTTPEndpoint, a.config.Safety.HTTPLimitA, a.config.Safety.HTTPLimitB)
	}
	a.devices.Use(adapter)
	a.addLog("正在连接设备…")
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
		defer cancel()
		err := adapter.Connect(ctx)
		a.mainWindow.Synchronize(func() {
			if err != nil {
				a.addLog("设备连接失败：" + err.Error())
			} else {
				a.addLog("设备连接流程已启动")
			}
			a.refreshSocketDetails()
			a.updateView()
		})
	}()
}

func (a *application) disconnectDevice() {
	adapter := a.devices.Adapter()
	if adapter != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		_ = adapter.Disconnect(ctx)
		cancel()
	}
	a.outputActive = false
	a.session.Connected = false
	a.addLog("设备连接已断开")
	a.updateView()
}

func (a *application) stopDevice(message string) {
	adapter := a.devices.Adapter()
	if adapter != nil && adapter.Status().Connected {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		if err := adapter.Stop(ctx); err != nil {
			a.addLog("设备停止失败：" + err.Error())
		}
		cancel()
	}
	a.outputActive = false
	a.outputEnd = time.Time{}
	if message != "" {
		a.addLog(message)
	}
	a.updateView()
}

func (a *application) applyBLESafety() {
	adapter, ok := a.devices.Adapter().(*device.BLEAdapter)
	if !ok {
		a.addLog("BF 参数仅能在蓝牙 V3 已连接时应用")
		return
	}
	if err := adapter.ApplySafety(context.Background()); err != nil {
		a.addLog("BF 参数写入失败：" + err.Error())
	} else {
		a.addLog("BF 安全参数已重新应用")
	}
}

func (a *application) currentDeviceStatus() device.Status {
	if adapter := a.devices.Adapter(); adapter != nil {
		return adapter.Status()
	}
	return device.Status{Text: "未连接", Source: "未连接"}
}

func (a *application) updateView() {
	status := a.currentDeviceStatus()
	a.session.Connected = status.Connected
	a.statusValue.SetText(a.session.StatusText())
	a.sessionValue.SetText(formatSeconds(a.session.SessionSeconds))
	a.leftValue.SetText(formatSeconds(a.session.LeftSeconds))
	a.distractValue.SetText(formatSeconds(a.session.DistractionSeconds))
	a.idleValue.SetText(formatSeconds(a.session.IdleSeconds))
	if status.Known {
		a.strengthValue.SetText(fmt.Sprintf("A %d  |  B %d", status.ActualA, status.ActualB))
	} else {
		a.strengthValue.SetText("A --  |  B --")
	}
	a.strengthSource.SetText(status.Source)
	a.deviceValue.SetText(status.Text)
	a.deviceBadge.SetText(status.Text)
	a.lockBadge.SetText(map[bool]string{true: "已锁定", false: "未锁定"}[a.session.Locked])
	a.unlockButton.SetEnabled(a.session.Locked)
	a.refreshSocketDetails()
	a.updateFloatingMonitors()
}

func (a *application) refreshSocketDetails() {
	adapter, ok := a.devices.Adapter().(*device.SocketAdapter)
	if !ok {
		return
	}
	status := adapter.Status()
	a.socketStatus.SetText(status.Text)
	if status.HasLimits {
		a.socketLimits.SetText(fmt.Sprintf("当前 A=%d / 上限 %d；B=%d / 上限 %d（来自 App）", status.ActualA, status.LimitA, status.ActualB, status.LimitB))
	} else {
		a.socketLimits.SetText("等待 App 上报 A/B 强度上限；未上报前禁止输出")
	}
	text := adapter.QRText()
	a.socketAddress.SetText(text)
	a.socketQRText.SetText(text)
	if text != "" {
		a.updateQRCode(text)
	}
}

func (a *application) updateQRCode(text string) {
	path := filepath.Join(os.TempDir(), "oc-writing-focus-go-qr.png")
	if qrcode.WriteFile(text, qrcode.Medium, 200, path) != nil {
		return
	}
	image, err := walk.NewImageFromFile(path)
	if err == nil {
		a.socketQRImage.SetImage(image)
	}
}

func (a *application) addLog(message string) {
	a.logs = append([]string{"[" + time.Now().Format("15:04:05") + "] " + message}, a.logs...)
	if len(a.logs) > 80 {
		a.logs = a.logs[:80]
	}
	if a.logList != nil {
		_ = a.logList.SetModel(a.logs)
	}
}

func (a *application) onClosing(cancel *bool, reason walk.CloseReason) {
	select {
	case <-a.timerStop:
	default:
		close(a.timerStop)
	}
	if a.outputActive {
		a.stopDevice("")
	}
	if adapter := a.devices.Adapter(); adapter != nil {
		_ = adapter.Disconnect(context.Background())
	}
	if err := a.captureConfig(); err == nil {
		_ = appconfig.Save(a.config)
	}
	if a.channelWindow != nil {
		a.channelWindow.Close()
	}
	if a.windowMonitor != nil {
		a.windowMonitor.Close()
	}
}

func (a *application) limits() session.Limits {
	return session.Limits{SessionMinutes: a.config.Focus.SessionMinutes, LeaveSeconds: a.config.Focus.LeaveSeconds, IdleSeconds: a.config.Focus.IdleSeconds}
}

func formatSeconds(value int) string {
	if value < 0 {
		value = 0
	}
	return fmt.Sprintf("%02d:%02d", value/60, value%60)
}

func parseInt(edit *walk.LineEdit, fallback, minValue, maxValue int) int {
	value, err := strconv.Atoi(strings.TrimSpace(edit.Text()))
	if err != nil {
		return fallback
	}
	if value < minValue {
		return minValue
	}
	if value > maxValue {
		return maxValue
	}
	return value
}

func parseRange(edit *walk.LineEdit, fallback appconfig.Range) appconfig.Range {
	parts := strings.FieldsFunc(edit.Text(), func(r rune) bool { return r == '-' || r == '–' || r == ',' || r == '，' })
	if len(parts) != 2 {
		return fallback
	}
	low, e1 := strconv.Atoi(strings.TrimSpace(parts[0]))
	high, e2 := strconv.Atoi(strings.TrimSpace(parts[1]))
	if e1 != nil || e2 != nil || low < 0 || high > 200 || low > high {
		return fallback
	}
	return appconfig.Range{low, high}
}

func setAlwaysOnTop(window *walk.MainWindow) {
	const swpNoSize, swpNoMove = 0x0001, 0x0002
	syscall.NewLazyDLL("user32.dll").NewProc("SetWindowPos").Call(uintptr(window.Handle()), ^uintptr(0), 0, 0, 0, 0, swpNoSize|swpNoMove)
}

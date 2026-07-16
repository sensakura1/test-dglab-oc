//go:build windows

package main

import (
	"fmt"
	"strconv"

	"github.com/lxn/walk"

	appconfig "ocwritingfocus/goapp/internal/config"
	"ocwritingfocus/goapp/internal/monitor"
	"ocwritingfocus/goapp/internal/session"
)

func (a *application) applyConfigToUI() {
	c := a.config
	a.focusMinutes.SetText(strconv.Itoa(c.Focus.SessionMinutes))
	a.leaveSeconds.SetText(strconv.Itoa(c.Focus.LeaveSeconds))
	a.idleSeconds.SetText(strconv.Itoa(c.Focus.IdleSeconds))
	a.outputMode.SetCurrentIndex(indexOf(c.Trigger.OutputMode, "untilWhitelist", "fixedDuration"))
	a.overlapMode.SetCurrentIndex(indexOf(c.Trigger.OverlapMode, "restart", "extend"))
	a.channelMode.SetCurrentIndex(indexOf(c.Trigger.Channel, "both", "A", "B"))
	a.strengthA.SetText(fmt.Sprintf("%d-%d", c.Trigger.StrengthA[0], c.Trigger.StrengthA[1]))
	a.strengthB.SetText(fmt.Sprintf("%d-%d", c.Trigger.StrengthB[0], c.Trigger.StrengthB[1]))
	a.waveform.SetCurrentIndex(indexOf(c.Trigger.Waveform, "constant", "pulse", "ramp", "heartbeat"))
	a.wavePeriod.SetText(strconv.Itoa(c.Trigger.WavePeriodMs))
	a.waveIntensity.SetText(strconv.Itoa(c.Trigger.WaveIntensity))
	a.duration.SetText(strconv.Itoa(c.Trigger.DurationSeconds))
	a.maxContinuous.SetText(strconv.Itoa(c.Trigger.MaxContinuousSeconds))
	a.cooldown.SetText(strconv.Itoa(c.Trigger.CooldownSeconds))
	a.deviceMode.SetCurrentIndex(indexOf(c.Device.Mode, "http", "ble", "socket"))
	a.httpEndpoint.SetText(c.Device.HTTPEndpoint)
	a.bleAddress.SetText(c.Device.BLEAddress)
	a.socketMode.SetCurrentIndex(indexOf(c.Device.Socket.Mode, "local", "remote"))
	a.localHost.SetText(c.Device.Socket.LocalHost)
	a.localPort.SetText(strconv.Itoa(c.Device.Socket.LocalPort))
	a.remoteServer.SetText(c.Device.Socket.RemoteServer)
	a.httpLimitA.SetText(strconv.Itoa(c.Safety.HTTPLimitA))
	a.httpLimitB.SetText(strconv.Itoa(c.Safety.HTTPLimitB))
	a.softLimitA.SetText(strconv.Itoa(c.Safety.SoftLimitA))
	a.softLimitB.SetText(strconv.Itoa(c.Safety.SoftLimitB))
	a.freqBalanceA.SetText(strconv.Itoa(c.Safety.FrequencyBalanceA))
	a.freqBalanceB.SetText(strconv.Itoa(c.Safety.FrequencyBalanceB))
	a.strengthBalanceA.SetText(strconv.Itoa(c.Safety.StrengthBalanceA))
	a.strengthBalanceB.SetText(strconv.Itoa(c.Safety.StrengthBalanceB))
	_ = a.whitelist.SetModel(c.Scope.Whitelist)
	_ = a.blacklist.SetModel(c.Scope.Blacklist)
	a.onDeviceModeChanged()
	a.updateView()
}

func (a *application) captureConfig() error {
	c := a.config
	c.SchemaVersion = appconfig.SchemaVersion
	c.Focus.SessionMinutes = parseInt(a.focusMinutes, 45, 1, 10080)
	c.Focus.LeaveSeconds = parseInt(a.leaveSeconds, 300, 1, 86400)
	c.Focus.IdleSeconds = parseInt(a.idleSeconds, 600, 1, 86400)
	c.Trigger.OutputMode = choice(a.outputMode.CurrentIndex(), "untilWhitelist", "fixedDuration")
	c.Trigger.OverlapMode = choice(a.overlapMode.CurrentIndex(), "restart", "extend")
	c.Trigger.Channel = choice(a.channelMode.CurrentIndex(), "both", "A", "B")
	c.Trigger.StrengthA = parseRange(a.strengthA, appconfig.Range{10, 20})
	c.Trigger.StrengthB = parseRange(a.strengthB, appconfig.Range{10, 20})
	c.Trigger.Waveform = choice(a.waveform.CurrentIndex(), "constant", "pulse", "ramp", "heartbeat")
	c.Trigger.WavePeriodMs = parseInt(a.wavePeriod, 30, 10, 1000)
	c.Trigger.WaveIntensity = parseInt(a.waveIntensity, 20, 0, 100)
	c.Trigger.DurationSeconds = parseInt(a.duration, 1, 1, 30)
	c.Trigger.MaxContinuousSeconds = parseInt(a.maxContinuous, 10, 1, 30)
	c.Trigger.CooldownSeconds = parseInt(a.cooldown, 60, 5, 3600)
	c.Device.Mode = choice(a.deviceMode.CurrentIndex(), "http", "ble", "socket")
	c.Device.HTTPEndpoint = a.httpEndpoint.Text()
	c.Device.BLEAddress = a.bleAddress.Text()
	c.Device.Socket.Mode = choice(a.socketMode.CurrentIndex(), "local", "remote")
	c.Device.Socket.LocalHost = a.localHost.Text()
	c.Device.Socket.LocalPort = parseInt(a.localPort, 5678, 1, 65535)
	c.Device.Socket.RemoteServer = a.remoteServer.Text()
	c.Safety.HTTPLimitA = parseInt(a.httpLimitA, 30, 0, 200)
	c.Safety.HTTPLimitB = parseInt(a.httpLimitB, 30, 0, 200)
	c.Safety.SoftLimitA = parseInt(a.softLimitA, 30, 0, 200)
	c.Safety.SoftLimitB = parseInt(a.softLimitB, 30, 0, 200)
	c.Safety.FrequencyBalanceA = parseInt(a.freqBalanceA, 0, 0, 255)
	c.Safety.FrequencyBalanceB = parseInt(a.freqBalanceB, 0, 0, 255)
	c.Safety.StrengthBalanceA = parseInt(a.strengthBalanceA, 0, 0, 255)
	c.Safety.StrengthBalanceB = parseInt(a.strengthBalanceB, 0, 0, 255)
	c.Scope.Whitelist = append([]string{}, a.config.Scope.Whitelist...)
	c.Scope.Blacklist = append([]string{}, a.config.Scope.Blacklist...)
	if err := c.Validate(); err != nil {
		return err
	}
	a.config = c
	return nil
}

func (a *application) refreshWindowPicker() {
	windows := monitor.VisibleWindows()
	a.windowItems = make([]string, 0, len(windows))
	for _, item := range windows {
		a.windowItems = append(a.windowItems, item.Display())
	}
	_ = a.windowPicker.SetModel(a.windowItems)
	if len(a.windowItems) > 0 {
		a.windowPicker.SetCurrentIndex(0)
	}
	a.addLog(fmt.Sprintf("已刷新窗口列表：%d 个窗口", len(a.windowItems)))
}

func (a *application) selectedWindow() string {
	index := a.windowPicker.CurrentIndex()
	if index < 0 || index >= len(a.windowItems) {
		return ""
	}
	return a.windowItems[index]
}

func (a *application) addWhitelist() {
	value := a.selectedWindow()
	if value == "" || contains(a.config.Scope.Whitelist, value) {
		return
	}
	a.config.Scope.Whitelist = append(a.config.Scope.Whitelist, value)
	_ = a.whitelist.SetModel(a.config.Scope.Whitelist)
	a.addLog("已添加窗口白名单：" + value)
	a.refreshWindow()
}

func (a *application) removeWhitelist() {
	index := a.whitelist.CurrentIndex()
	if index < 0 || index >= len(a.config.Scope.Whitelist) {
		return
	}
	value := a.config.Scope.Whitelist[index]
	a.config.Scope.Whitelist = append(a.config.Scope.Whitelist[:index], a.config.Scope.Whitelist[index+1:]...)
	_ = a.whitelist.SetModel(a.config.Scope.Whitelist)
	a.addLog("已删除白名单：" + value)
}

func (a *application) addBlacklist() {
	value := a.selectedWindow()
	if value == "" || contains(a.config.Scope.Blacklist, value) {
		return
	}
	a.config.Scope.Blacklist = append(a.config.Scope.Blacklist, value)
	_ = a.blacklist.SetModel(a.config.Scope.Blacklist)
	a.addLog("已添加窗口黑名单：" + value)
	a.refreshWindow()
}

func (a *application) removeBlacklist() {
	index := a.blacklist.CurrentIndex()
	if index < 0 || index >= len(a.config.Scope.Blacklist) {
		return
	}
	value := a.config.Scope.Blacklist[index]
	a.config.Scope.Blacklist = append(a.config.Scope.Blacklist[:index], a.config.Scope.Blacklist[index+1:]...)
	_ = a.blacklist.SetModel(a.config.Scope.Blacklist)
	a.addLog("已删除黑名单：" + value)
}

func (a *application) importConfig() {
	dialog := new(walk.FileDialog)
	dialog.Title = "导入桌面配置"
	dialog.Filter = "JSON 配置文件 (*.json)|*.json|所有文件 (*.*)|*.*"
	ok, err := dialog.ShowOpen(a.mainWindow)
	if err != nil || !ok {
		return
	}
	value, err := appconfig.LoadFile(dialog.FilePath)
	if err != nil {
		a.showError("配置导入失败", err)
		return
	}
	a.disconnectDevice()
	a.config = value
	a.session = session.New(a.limits())
	a.applyConfigToUI()
	a.addLog("配置已导入：" + dialog.FilePath)
}

func (a *application) exportConfig() {
	if err := a.captureConfig(); err != nil {
		a.showError("配置无效", err)
		return
	}
	dialog := new(walk.FileDialog)
	dialog.Title = "导出桌面配置"
	dialog.Filter = "JSON 配置文件 (*.json)|*.json"
	dialog.FilePath = "oc-writing-focus-config.json"
	ok, err := dialog.ShowSave(a.mainWindow)
	if err != nil || !ok {
		return
	}
	if err := appconfig.SaveFile(dialog.FilePath, a.config); err != nil {
		a.showError("配置导出失败", err)
		return
	}
	a.addLog("配置已导出：" + dialog.FilePath)
}

func (a *application) resetSafeConfig() {
	a.disconnectDevice()
	a.config = appconfig.SafeDefaults()
	a.session = session.New(a.limits())
	a.applyConfigToUI()
	a.addLog("已恢复安全默认配置")
}

func (a *application) showError(title string, err error) {
	walk.MsgBox(a.mainWindow, title, err.Error(), walk.MsgBoxIconError)
}
func contains(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}
func indexOf(value string, values ...string) int {
	for i, candidate := range values {
		if value == candidate {
			return i
		}
	}
	return 0
}
func choice(index int, values ...string) string {
	if index < 0 || index >= len(values) {
		return values[0]
	}
	return values[index]
}

//go:build windows

package main

import (
	"fmt"
	"time"

	"github.com/lxn/walk"
	. "github.com/lxn/walk/declarative"
)

func (a *application) openChannelMonitor() {
	if a.channelWindow != nil {
		a.channelWindow.SetFocus()
		return
	}
	status := a.currentDeviceStatus()
	strength := "A --     B --"
	if status.Known {
		strength = fmt.Sprintf("A %d     B %d", status.ActualA, status.ActualB)
	}
	err := (MainWindow{
		AssignTo: &a.channelWindow, Title: "A/B 强度监控", MinSize: Size{Width: 330, Height: 190}, Size: Size{Width: 400, Height: 240},
		Background: SolidColorBrush{Color: colorRoot}, Layout: VBox{}, Children: []Widget{
			Label{Text: "A/B 通道实时监控", TextColor: colorInk, Font: Font{Bold: true, PointSize: 12}},
			VSpacer{}, Label{AssignTo: &a.channelStrength, Text: strength, TextColor: colorBlue, Font: Font{Bold: true, PointSize: 24}}, VSpacer{},
			Composite{Layout: HBox{}, Children: []Widget{
				Label{AssignTo: &a.channelDuration, Text: "本次持续：--", TextColor: colorInk}, HSpacer{},
				Label{AssignTo: &a.channelRemaining, Text: "剩余时间：未输出", TextColor: colorInk},
			}},
			Label{AssignTo: &a.channelSource, Text: status.Source, TextColor: colorMuted},
		},
	}).Create()
	if err != nil {
		a.showError("无法打开通道悬浮窗", err)
		return
	}
	setAlwaysOnTop(a.channelWindow)
	a.channelWindow.Closing().Attach(func(_ *bool, _ walk.CloseReason) {
		a.channelWindow, a.channelStrength, a.channelDuration, a.channelRemaining, a.channelSource = nil, nil, nil, nil, nil
	})
	a.channelWindow.Show()
}

func (a *application) openWindowMonitor() {
	if a.windowMonitor != nil {
		a.windowMonitor.SetFocus()
		return
	}
	err := (MainWindow{
		AssignTo: &a.windowMonitor, Title: "当前窗口监控", MinSize: Size{Width: 360, Height: 190}, Size: Size{Width: 520, Height: 240},
		Background: SolidColorBrush{Color: colorRoot}, Layout: VBox{}, Children: []Widget{
			Label{Text: "Windows 前台窗口实时监控", TextColor: colorInk, Font: Font{Bold: true, PointSize: 12}},
			VSpacer{}, Label{AssignTo: &a.floatingWindow, Text: a.currentWindow.Text(), TextColor: colorBlue, Font: Font{Bold: true, PointSize: 14}}, VSpacer{},
			Label{AssignTo: &a.floatingMatch, Text: "范围判定：" + a.currentMatch.Text() + "  /  每 1 秒刷新", TextColor: colorInk},
		},
	}).Create()
	if err != nil {
		a.showError("无法打开窗口悬浮窗", err)
		return
	}
	setAlwaysOnTop(a.windowMonitor)
	a.windowMonitor.Closing().Attach(func(_ *bool, _ walk.CloseReason) { a.windowMonitor, a.floatingWindow, a.floatingMatch = nil, nil, nil })
	a.windowMonitor.Show()
}

func (a *application) updateFloatingMonitors() {
	if a.channelWindow != nil {
		status := a.currentDeviceStatus()
		if status.Known {
			a.channelStrength.SetText(fmt.Sprintf("A %d     B %d", status.ActualA, status.ActualB))
		} else {
			a.channelStrength.SetText("A --     B --")
		}
		duration := a.config.Trigger.DurationSeconds
		if a.outputActive && a.outputProfile.HoldUntilWhitelist {
			duration = int(a.outputProfile.MaxContinuous / time.Second)
		}
		a.channelDuration.SetText(fmt.Sprintf("本次持续：%d 秒", duration))
		if a.outputActive {
			a.channelRemaining.SetText(fmt.Sprintf("剩余时间：%.1f 秒", maxFloat(0, time.Until(a.outputEnd).Seconds())))
		} else {
			a.channelRemaining.SetText("剩余时间：未输出")
		}
		a.channelSource.SetText(status.Source)
	}
}

func maxFloat(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

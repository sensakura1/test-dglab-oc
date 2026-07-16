//go:build windows

package main

import (
	"github.com/lxn/walk"
	. "github.com/lxn/walk/declarative"
)

var (
	colorInk     = walk.RGB(232, 232, 232)
	colorMuted   = walk.RGB(160, 160, 160)
	colorRoot    = walk.RGB(24, 24, 24)
	colorPanel   = walk.RGB(38, 38, 38)
	colorCard    = walk.RGB(48, 48, 48)
	colorSidebar = walk.RGB(30, 30, 30)
	colorBlue    = walk.RGB(102, 179, 255)
)

func text(value string) Label  { return Label{Text: value, TextColor: colorInk} }
func muted(value string) Label { return Label{Text: value, TextColor: colorMuted} }
func title(value string) Label {
	return Label{Text: value, TextColor: colorInk, Font: Font{Bold: true, PointSize: 14}}
}

func (a *application) createMainWindow() error {
	err := (MainWindow{
		AssignTo:   &a.mainWindow,
		Title:      "OC 设定写作督促工具 - Go",
		MinSize:    Size{Width: 1080, Height: 700},
		Size:       Size{Width: 1280, Height: 820},
		Background: SolidColorBrush{Color: colorRoot},
		Layout:     HBox{MarginsZero: true, SpacingZero: true},
		Children: []Widget{
			Composite{
				MinSize: Size{Width: 210}, MaxSize: Size{Width: 210},
				Background: SolidColorBrush{Color: colorSidebar},
				Layout:     VBox{Margins: Margins{Left: 18, Top: 22, Right: 18, Bottom: 18}},
				Children: []Widget{
					Label{Text: "OC WRITING FOCUS", TextColor: colorBlue, Font: Font{Bold: true, PointSize: 11}},
					Label{Text: "写作督促工具", TextColor: colorInk, Font: Font{Bold: true, PointSize: 16}},
					muted("Go 原生 Windows 版"),
					VSpacer{Size: 22},
					PushButton{Text: "控制台", OnClicked: func() { a.showPage("dashboard") }},
					PushButton{Text: "范围规则", OnClicked: func() { a.showPage("scope") }},
					PushButton{Text: "触发设置", OnClicked: func() { a.showPage("trigger") }},
					PushButton{Text: "设备与安全", OnClicked: func() { a.showPage("device") }},
					PushButton{Text: "日志", OnClicked: func() { a.showPage("logs") }},
					VSpacer{},
					muted("本地监测 · 不保存窗口历史"),
					muted("默认安全上限 · 急停优先"),
				},
			},
			Composite{
				Background: SolidColorBrush{Color: colorRoot}, StretchFactor: 1,
				Layout: VBox{Margins: Margins{Left: 20, Top: 14, Right: 20, Bottom: 14}},
				Children: []Widget{
					Composite{Background: SolidColorBrush{Color: colorPanel}, Layout: HBox{Margins: Margins{Left: 14, Top: 9, Right: 14, Bottom: 9}}, Children: []Widget{
						Composite{Layout: VBox{MarginsZero: true}, Children: []Widget{
							Label{AssignTo: &a.pageEye, Text: "FOCUS SESSION / DASHBOARD", TextColor: colorMuted, Font: Font{Bold: true, PointSize: 8}},
							Label{AssignTo: &a.pageTitle, Text: "控制台", TextColor: colorInk, Font: Font{Bold: true, PointSize: 17}},
						}},
						HSpacer{},
						Composite{Layout: VBox{MarginsZero: true}, Children: []Widget{
							Label{AssignTo: &a.strengthValue, Text: "A --  |  B --", TextColor: colorInk, Font: Font{Bold: true, PointSize: 11}},
							Label{AssignTo: &a.strengthSource, Text: "未连接", TextColor: colorMuted, Font: Font{PointSize: 8}},
						}},
						Label{AssignTo: &a.deviceBadge, Text: "HTTP 桥接", TextColor: colorBlue, Font: Font{Bold: true}},
						Label{AssignTo: &a.lockBadge, Text: "未锁定", TextColor: colorBlue, Font: Font{Bold: true}},
						PushButton{Text: "通道悬浮", OnClicked: a.openChannelMonitor},
						PushButton{Text: "窗口悬浮", OnClicked: a.openWindowMonitor},
						PushButton{Text: "急停", OnClicked: a.emergencyStop},
					}},
					ScrollView{Background: SolidColorBrush{Color: colorRoot}, Layout: VBox{Margins: Margins{Top: 8}}, StretchFactor: 1, Children: []Widget{
						a.dashboardPage(), a.scopePage(), a.triggerPage(), a.devicePage(), a.logsPage(),
					}},
				},
			},
		},
	}).Create()
	if err != nil {
		return err
	}
	a.pages = map[string]*walk.Composite{"dashboard": a.dashboardView, "scope": a.scopeView, "trigger": a.triggerView, "device": a.deviceView, "logs": a.logsView}
	a.deviceMode.CurrentIndexChanged().Attach(a.onDeviceModeChanged)
	a.socketMode.CurrentIndexChanged().Attach(a.onSocketModeChanged)
	return nil
}

func (a *application) dashboardPage() Widget {
	return Composite{AssignTo: &a.dashboardView, Background: SolidColorBrush{Color: colorRoot}, Layout: VBox{}, Children: []Widget{
		Composite{Background: SolidColorBrush{Color: colorPanel}, Layout: VBox{Margins: Margins{Left: 16, Top: 16, Right: 16, Bottom: 16}}, Children: []Widget{
			title("当前专注窗口"), muted("实时读取 Windows 前台窗口，并立即与范围规则匹配。"),
			LineEdit{AssignTo: &a.currentWindow, ReadOnly: true, Text: "等待检测..."},
			Composite{Layout: HBox{MarginsZero: true}, Children: []Widget{muted("范围判定："), Label{AssignTo: &a.currentMatch, Text: "未匹配", TextColor: colorBlue, Font: Font{Bold: true}}, HSpacer{}, muted("Windows 前台窗口 · 每 1 秒")}},
		}},
		Composite{Background: SolidColorBrush{Color: colorPanel}, Layout: VBox{Margins: Margins{Left: 16, Top: 16, Right: 16, Bottom: 16}}, Children: []Widget{
			Composite{Layout: HBox{MarginsZero: true}, Children: []Widget{
				Composite{Layout: VBox{MarginsZero: true}, Children: []Widget{muted("当前状态"), Label{AssignTo: &a.statusValue, Text: "未开始", TextColor: colorInk, Font: Font{Bold: true, PointSize: 22}}}},
				HSpacer{}, Label{AssignTo: &a.sessionValue, Text: "45:00", TextColor: colorBlue, Font: Font{Bold: true, PointSize: 30}},
			}},
			Composite{Layout: Grid{Columns: 3}, Children: []Widget{
				Composite{Background: SolidColorBrush{Color: colorCard}, Layout: VBox{}, Children: []Widget{muted("离开计时"), Label{AssignTo: &a.leftValue, Text: "00:00", TextColor: colorInk, Font: Font{Bold: true, PointSize: 16}}}},
				Composite{Background: SolidColorBrush{Color: colorCard}, Layout: VBox{}, Children: []Widget{muted("分心计时"), Label{AssignTo: &a.distractValue, Text: "00:00", TextColor: colorInk, Font: Font{Bold: true, PointSize: 16}}}},
				Composite{Background: SolidColorBrush{Color: colorCard}, Layout: VBox{}, Children: []Widget{muted("全局无输入"), Label{AssignTo: &a.idleValue, Text: "00:00", TextColor: colorInk, Font: Font{Bold: true, PointSize: 16}}}},
			}},
			Composite{Layout: HBox{}, Children: []Widget{
				PushButton{Text: "开始专注", OnClicked: a.startFocus}, PushButton{Text: "暂停/恢复", OnClicked: a.togglePause},
				PushButton{Text: "结束", OnClicked: a.endFocus}, PushButton{AssignTo: &a.unlockButton, Text: "解除锁定", Enabled: false, OnClicked: a.unlock},
				PushButton{Text: "测试触发", OnClicked: func() { a.trigger("手动测试") }}, HSpacer{},
			}},
		}},
	}}
}

func (a *application) scopePage() Widget {
	return Composite{AssignTo: &a.scopeView, Visible: false, Background: SolidColorBrush{Color: colorRoot}, Layout: VBox{}, Children: []Widget{
		Composite{Background: SolidColorBrush{Color: colorPanel}, Layout: VBox{}, Children: []Widget{
			title("窗口选择器"), muted("从当前可见窗口中选择目标，再加入白名单或黑名单。"),
			ComboBox{AssignTo: &a.windowPicker}, PushButton{Text: "刷新窗口列表", OnClicked: a.refreshWindowPicker},
		}},
		Composite{Background: SolidColorBrush{Color: colorPanel}, Layout: Grid{Columns: 2}, Children: []Widget{
			Composite{Layout: VBox{}, Children: []Widget{
				title("窗口白名单"), muted("命中后视为正常写作窗口，不执行离开惩罚。"),
				Composite{Layout: HBox{}, Children: []Widget{PushButton{Text: "添加白名单", OnClicked: a.addWhitelist}, PushButton{Text: "删除选中", OnClicked: a.removeWhitelist}}},
				ListBox{AssignTo: &a.whitelist, MinSize: Size{Height: 280}},
			}},
			Composite{Layout: VBox{}, Children: []Widget{
				title("窗口黑名单"), muted("命中后立即触发，并持续到返回白名单。"),
				Composite{Layout: HBox{}, Children: []Widget{PushButton{Text: "添加黑名单", OnClicked: a.addBlacklist}, PushButton{Text: "删除选中", OnClicked: a.removeBlacklist}}},
				ListBox{AssignTo: &a.blacklist, MinSize: Size{Height: 280}},
			}},
		}},
	}}
}

func (a *application) triggerPage() Widget {
	return Composite{AssignTo: &a.triggerView, Visible: false, Background: SolidColorBrush{Color: colorRoot}, Layout: VBox{}, Children: []Widget{
		Composite{Background: SolidColorBrush{Color: colorPanel}, Layout: VBox{}, Children: []Widget{
			title("触发策略"), muted("与现有桌面版相同：离开、全局无输入、输出结束方式和重复触发处理。"),
			Composite{Layout: Grid{Columns: 4}, Children: []Widget{
				muted("专注时长（分钟）"), LineEdit{AssignTo: &a.focusMinutes}, muted("离开触发（秒）"), LineEdit{AssignTo: &a.leaveSeconds},
				muted("Windows 全局无输入（秒）"), LineEdit{AssignTo: &a.idleSeconds}, muted("输出结束方式"), ComboBox{AssignTo: &a.outputMode, Model: []string{"返回白名单时停止", "固定时长后停止"}},
				muted("重复触发处理"), ComboBox{AssignTo: &a.overlapMode, Model: []string{"重新计时", "叠加时长"}}, muted("黑名单策略"), LineEdit{ReadOnly: true, Text: "命中立即触发"},
				muted("持续模式最长输出（秒）"), LineEdit{AssignTo: &a.maxContinuous}, muted("持续模式冷却（秒）"), LineEdit{AssignTo: &a.cooldown},
			}},
		}},
		Composite{Background: SolidColorBrush{Color: colorPanel}, Layout: VBox{}, Children: []Widget{
			title("郊狼输出配置"), muted("V3 原始强度 0–200；Socket 波形由 App 决定，强度和持续时间使用本软件设置。"),
			Composite{Layout: Grid{Columns: 6}, Children: []Widget{
				muted("输出通道"), ComboBox{AssignTo: &a.channelMode, Model: []string{"A + B 双通道", "仅 A 通道", "仅 B 通道"}}, muted("A 强度范围"), LineEdit{AssignTo: &a.strengthA}, muted("B 强度范围"), LineEdit{AssignTo: &a.strengthB},
				muted("波形"), ComboBox{AssignTo: &a.waveform, Model: []string{"恒定", "间歇", "渐强", "心跳"}}, muted("波形周期 ms"), LineEdit{AssignTo: &a.wavePeriod}, muted("波形强度"), LineEdit{AssignTo: &a.waveIntensity},
				muted("固定持续时间（秒）"), LineEdit{AssignTo: &a.duration}, muted("安全说明"), muted("强度受设备 A/B 上限二次限制；急停立即归零。"), HSpacer{}, HSpacer{},
			}},
		}},
	}}
}

func (a *application) devicePage() Widget {
	return Composite{AssignTo: &a.deviceView, Visible: false, Background: SolidColorBrush{Color: colorRoot}, Layout: VBox{}, Children: []Widget{
		Composite{Background: SolidColorBrush{Color: colorPanel}, Layout: VBox{}, Children: []Widget{
			Composite{Layout: HBox{}, Children: []Widget{title("设备连接与强度安全上限"), HSpacer{}, muted("设备状态："), Label{AssignTo: &a.deviceValue, Text: "未连接", TextColor: colorBlue, Font: Font{Bold: true}}}},
			muted("Socket 使用 App 上报上限；蓝牙和 HTTP 使用本页手动上限。"),
			Composite{Layout: HBox{}, Children: []Widget{muted("连接模式"), ComboBox{AssignTo: &a.deviceMode, Model: []string{"HTTP 真实设备桥接", "蓝牙 V3 直连", "Socket 控制协议"}}, HSpacer{}}},
			Composite{AssignTo: &a.httpPanel, Background: SolidColorBrush{Color: colorCard}, Layout: Grid{Columns: 4}, Children: []Widget{
				title("HTTP 真实设备桥接"), HSpacer{}, HSpacer{}, HSpacer{},
				muted("桥接服务地址"), LineEdit{AssignTo: &a.httpEndpoint, ColumnSpan: 3},
				muted("A 手动上限"), LineEdit{AssignTo: &a.httpLimitA}, muted("B 手动上限"), LineEdit{AssignTo: &a.httpLimitB},
			}},
			Composite{AssignTo: &a.blePanel, Visible: false, Background: SolidColorBrush{Color: colorCard}, Layout: Grid{Columns: 4}, Children: []Widget{
				title("蓝牙 V3 直连"), HSpacer{}, HSpacer{}, HSpacer{},
				muted("12 位蓝牙地址"), LineEdit{AssignTo: &a.bleAddress, ColumnSpan: 3},
				muted("A 软上限"), LineEdit{AssignTo: &a.softLimitA}, muted("B 软上限"), LineEdit{AssignTo: &a.softLimitB},
				muted("A 频率平衡"), LineEdit{AssignTo: &a.freqBalanceA}, muted("B 频率平衡"), LineEdit{AssignTo: &a.freqBalanceB},
				muted("A 脉宽平衡"), LineEdit{AssignTo: &a.strengthBalanceA}, muted("B 脉宽平衡"), LineEdit{AssignTo: &a.strengthBalanceB},
			}},
			Composite{AssignTo: &a.socketPanel, Visible: false, Background: SolidColorBrush{Color: colorCard}, Layout: Grid{Columns: 4}, Children: []Widget{
				title("DG-Lab Socket 控制协议"), HSpacer{}, HSpacer{}, HSpacer{},
				muted("服务器方式"), ComboBox{AssignTo: &a.socketMode, Model: []string{"在本机建立 Socket 服务器", "连接外部 Socket 服务器"}}, muted("监听端口"), LineEdit{AssignTo: &a.localPort},
				muted("本机 IP / 域名"), LineEdit{AssignTo: &a.localHost}, muted("外部服务器"), LineEdit{AssignTo: &a.remoteServer},
				muted("绑定状态"), Label{AssignTo: &a.socketStatus, Text: "未连接服务器", TextColor: colorInk, ColumnSpan: 3},
				muted("App 当前强度 / 上限"), Label{AssignTo: &a.socketLimits, Text: "等待 App 上报 A/B 强度上限；未上报前禁止输出", TextColor: colorInk, ColumnSpan: 3},
				muted("App 手动连接地址"), LineEdit{AssignTo: &a.socketAddress, ReadOnly: true, ColumnSpan: 3},
				muted("二维码内容"), LineEdit{AssignTo: &a.socketQRText, ReadOnly: true, ColumnSpan: 2}, ImageView{AssignTo: &a.socketQRImage, MinSize: Size{Width: 150, Height: 150}},
			}},
			Composite{Layout: HBox{}, Children: []Widget{
				PushButton{AssignTo: &a.connectButton, Text: "连接 HTTP 桥接", OnClicked: a.connectDevice},
				PushButton{AssignTo: &a.applySafetyButton, Text: "重新应用 BF 参数", Visible: false, OnClicked: a.applyBLESafety},
				PushButton{Text: "断开", OnClicked: a.disconnectDevice}, PushButton{Text: "立即停止 A/B", OnClicked: func() { a.stopDevice("已手动停止 A/B") }},
			}},
		}},
	}}
}

func (a *application) logsPage() Widget {
	return Composite{AssignTo: &a.logsView, Visible: false, Background: SolidColorBrush{Color: colorRoot}, Layout: VBox{}, Children: []Widget{
		Composite{Background: SolidColorBrush{Color: colorPanel}, Layout: VBox{}, Children: []Widget{
			title("配置管理"), muted("导入会先停止当前输出并断开设备；配置文件与现有桌面版共用 schemaVersion 2。"),
			Composite{Layout: HBox{}, Children: []Widget{
				PushButton{Text: "导入配置", OnClicked: a.importConfig}, PushButton{Text: "导出配置", OnClicked: a.exportConfig},
				PushButton{Text: "恢复安全默认值", OnClicked: a.resetSafeConfig}, HSpacer{},
			}},
		}},
		Composite{Background: SolidColorBrush{Color: colorPanel}, Layout: VBox{}, Children: []Widget{
			Composite{Layout: HBox{}, Children: []Widget{title("最近日志"), HSpacer{}, PushButton{Text: "清空", OnClicked: func() { a.logs = nil; _ = a.logList.SetModel(a.logs) }}}},
			ListBox{AssignTo: &a.logList, MinSize: Size{Height: 420}},
		}},
	}}
}

func (a *application) showPage(name string) {
	for pageName, page := range a.pages {
		page.SetVisible(pageName == name)
	}
	titles := map[string][2]string{
		"dashboard": {"FOCUS SESSION / DASHBOARD", "控制台"}, "scope": {"FOCUS SESSION / SCOPE RULES", "范围规则"},
		"trigger": {"FOCUS SESSION / TRIGGER PROFILE", "触发设置"}, "device": {"FOCUS SESSION / DEVICE SAFETY", "设备与安全"},
		"logs": {"FOCUS SESSION / EVENT LOG", "日志"},
	}
	a.pageEye.SetText(titles[name][0])
	a.pageTitle.SetText(titles[name][1])
	if name == "scope" {
		a.refreshWindowPicker()
	}
}

func (a *application) onDeviceModeChanged() {
	index := a.deviceMode.CurrentIndex()
	a.httpPanel.SetVisible(index == 0)
	a.blePanel.SetVisible(index == 1)
	a.socketPanel.SetVisible(index == 2)
	a.applySafetyButton.SetVisible(index == 1)
	switch index {
	case 1:
		a.connectButton.SetText("连接并应用安全参数")
	case 2:
		a.connectButton.SetText(map[bool]string{true: "启动本地服务器并生成二维码", false: "连接外部服务器并生成二维码"}[a.socketMode.CurrentIndex() == 0])
	default:
		a.connectButton.SetText("连接 HTTP 桥接")
	}
}

func (a *application) onSocketModeChanged() {
	if a.deviceMode.CurrentIndex() == 2 {
		a.onDeviceModeChanged()
	}
}

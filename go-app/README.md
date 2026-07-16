# OC Writing Focus - Go 版本

Go 版本与现有桌面版使用相同的功能结构和 `schemaVersion: 2` 配置格式。

## 界面

- 相同的五页侧栏：控制台、范围规则、触发设置、设备与安全、日志。
- 相同的深色控制台布局、当前窗口状态、专注计时和安全状态信息。
- A/B 通道监控与当前窗口监控均为独立、置顶、可缩放窗口。

## 功能

- 每秒读取 Windows 当前前台窗口的进程名与标题。
- 从当前可见窗口选择并维护精确匹配的白名单和黑名单。
- 专注开始、暂停、结束，离开计时、全局无输入检测和周期结束触发。
- 返回白名单停止、固定时长、连续输出上限、冷却和紧急停止。
- HTTP 真实设备桥接，含可信明文地址限制和 A/B 手动上限。
- Windows WinRT BLE V3 直连，支持 BF 安全参数和 B0 输出/停止包。
- DG-Lab Socket 本地服务器与外部服务器模式，支持 App 上限、可靠停止及后台看门狗。
- 配置导入、导出、安全默认值和内存日志；不保存窗口标题历史。

配置保存在 `%AppData%\OCWritingFocus\go-config.json`，也可以导入或导出与现有桌面版相同格式的 JSON。

## 开发

```powershell
go test ./...
go build -ldflags "-H=windowsgui" -o build/OCWritingFocusGo.dev.exe ./cmd/ocwritingfocus
```

正式发布文件为 `dist/OCWritingFocusGo.exe`。

真实设备流程需要相应的 HTTP 桥接服务、DG-Lab App 或已配对的 V3 蓝牙设备；无设备时可以完成 UI、配置、规则和安全拦截验证。

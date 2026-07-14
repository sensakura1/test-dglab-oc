# 《OC 设定写作督促工具》开发文档索引

## 需求文档

- [开发需求文档](../OC_Writing_Focus_Coyote_Development_Requirements.md)

## 总开发文档

- [总软件开发文档](00_总软件开发文档.md)
- [软件文件目录结构](01_软件文件目录结构.md)

## 桌面应用

- 发布程序：`dist/OCWritingFocus.exe`，可直接双击运行，不需要通过 `.ps1` 启动。
- 启动命令：`npm start` 或 `npm run desktop`，两者都会直接运行 EXE。
- 重新构建：`npm run build:desktop`，WPF 脚本会作为资源内嵌进 EXE。
- EXE 宿主源码：[src/desktop/Program.cs](../src/desktop/Program.cs)
- 设备模式：HTTP 真实设备桥接、蓝牙 V3 直连。HTTP 桥接模式保留，用于连接已有本地郊狼桥接服务。
- 范围规则：参考 OBS 的窗口选择方式，先刷新当前可见窗口列表，再选择具体窗口加入白名单或黑名单；黑名单命中直接触发，白名单不处罚，未命中两者时按常规离开时间规则触发。
- 窗口检测：桌面端调用 Windows `EnumWindows`、`GetForegroundWindow`、`GetWindowText` 和 `GetWindowThreadProcessId` 读取窗口列表、当前前台窗口标题与进程名进行判定。

## 功能模块开发文档

- [配置管理模块](modules/01_配置管理模块.md)
- [活跃窗口监测模块](modules/02_活跃窗口监测模块.md)
- [输入与空闲监测模块](modules/03_输入与空闲监测模块.md)
- [范围匹配模块](modules/04_范围匹配模块.md)
- [专注会话模块](modules/05_专注会话模块.md)
- [触发规则引擎模块](modules/06_触发规则引擎模块.md)
- [郊狼设备适配模块](modules/07_郊狼设备适配模块.md)
- [安全急停模块](modules/08_安全急停模块.md)
- [日志与隐私模块](modules/09_日志与隐私模块.md)
- [用户界面模块](modules/10_用户界面模块.md)

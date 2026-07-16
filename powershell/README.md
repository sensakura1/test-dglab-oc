# PowerShell WPF 版本

此目录包含完整的 PowerShell 桌面端源码、测试和构建脚本：

- `src/desktop/`：WPF 应用入口、分片源码和 EXE 宿主源码
- `tests/desktop/`：PowerShell 桌面端测试
- `scripts/build-desktop.ps1`：PowerShell 版 EXE 构建脚本

在仓库根目录运行：

- `npm run desktop`：启动 PowerShell WPF 源码版本
- `npm test`：运行 JavaScript 与 PowerShell 测试
- `npm run build:desktop`：在获得发布确认后构建 `dist/OCWritingFocus.exe`

共享的二维码组件保留在仓库根目录 `vendor/QRCoder/`，发布产物统一保留在根目录 `dist/`。

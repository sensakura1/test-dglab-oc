# OC Writing Focus 主版本（C# + WPF）

此目录是项目的正式主版本。后续功能开发、缺陷修复、UI 调整和 EXE 发布默认在此 C# 项目中完成。运行时和发布文件均不依赖 PowerShell 源码。

目录结构：

- `src/OCWritingFocus.Core/`：配置、规则、会话和设备协议核心
- `src/OCWritingFocus.Wpf/`：Windows WPF 主程序及悬浮窗口
- `tests/OCWritingFocus.Core.Tests/`：C# 核心测试
- `OCWritingFocus.CSharp.sln`：主解决方案

从仓库根目录运行：

```powershell
npm start
npm run test:csharp
```

也可以直接使用 .NET CLI：

```powershell
dotnet run --project .\csharp\src\OCWritingFocus.Wpf\OCWritingFocus.Wpf.csproj
dotnet build .\csharp\OCWritingFocus.CSharp.sln -c Debug
dotnet run --project .\csharp\tests\OCWritingFocus.Core.Tests\OCWritingFocus.Core.Tests.csproj
```

获得用户明确发布确认后，运行 `npm run build:desktop`，生成根目录启动器 `dist/OCWritingFocus.exe` 和同级依赖目录 `dist/OCWritingFocus.dependencies/`。

启动器和依赖目录必须保持同级。依赖目录内包含自包含的 .NET 运行库、WPF 组件和设备依赖，目标电脑不需要预装 .NET。分发时必须同时复制 `OCWritingFocus.exe` 和 `OCWritingFocus.dependencies/`。

旧 PowerShell 版本保留在 `powershell/`，仅用于旧版维护、对照和回归验证。

$ErrorActionPreference = "Stop"

$powershellRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Split-Path -Parent $powershellRoot
$sourcePath = Join-Path $powershellRoot "src\desktop\Program.cs"
$scriptPath = Join-Path $powershellRoot "src\desktop\OCWritingFocusApp.Wpf.ps1"
$partsSourceDirectory = Join-Path $powershellRoot "src\desktop\parts"
$qrCoderPath = Join-Path $projectRoot "vendor\QRCoder\QRCoder.dll"
$outputDirectory = Join-Path $projectRoot "dist"
$outputPath = Join-Path $outputDirectory "OCWritingFocus.exe"
$appDirectory = Join-Path $outputDirectory "app"
$deployedScriptPath = Join-Path $appDirectory "OCWritingFocusApp.Wpf.ps1"
$deployedPartsDirectory = Join-Path $appDirectory "parts"
$deployedQrCoderPath = Join-Path $appDirectory "QRCoder.dll"
$automationAssembly = [System.Management.Automation.PSObject].Assembly.Location

$compilerCandidates = @(
  (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
  (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$compiler = $compilerCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $compiler) {
  throw "未找到 .NET Framework C# 编译器。"
}
if (-not (Test-Path $qrCoderPath)) {
  throw "未找到二维码组件 vendor\QRCoder\QRCoder.dll。"
}
if (-not (Test-Path $partsSourceDirectory -PathType Container)) {
  throw "未找到桌面程序分片目录 powershell\src\desktop\parts。"
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $appDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $deployedPartsDirectory -Force | Out-Null

$compilerArguments = @(
  "/nologo",
  "/target:winexe",
  "/platform:anycpu",
  "/optimize+",
  "/out:$outputPath",
  "/reference:$automationAssembly",
  "/reference:System.dll",
  "/reference:System.Core.dll",
  "/reference:System.Windows.Forms.dll",
  $sourcePath
)

& $compiler @compilerArguments
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $outputPath)) {
  throw "桌面 EXE 构建失败。"
}

Copy-Item -LiteralPath $scriptPath -Destination $deployedScriptPath -Force
Copy-Item -Path (Join-Path $partsSourceDirectory "*.ps1") -Destination $deployedPartsDirectory -Force
Copy-Item -LiteralPath $qrCoderPath -Destination $deployedQrCoderPath -Force

Write-Output "桌面目录版已生成：$outputDirectory"
Write-Output "启动程序：$outputPath"
Write-Output "外置资源：$appDirectory"


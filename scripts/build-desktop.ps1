$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot "src\desktop\Program.cs"
$scriptPath = Join-Path $projectRoot "src\desktop\OCWritingFocusApp.Wpf.ps1"
$outputDirectory = Join-Path $projectRoot "dist"
$outputPath = Join-Path $outputDirectory "OCWritingFocus.exe"
$automationAssembly = [System.Management.Automation.PSObject].Assembly.Location

$compilerCandidates = @(
  (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
  (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$compiler = $compilerCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $compiler) {
  throw "未找到 .NET Framework C# 编译器。"
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$compilerArguments = @(
  "/nologo",
  "/target:winexe",
  "/platform:anycpu",
  "/optimize+",
  "/out:$outputPath",
  "/resource:$scriptPath,OCWritingFocusApp.Wpf.ps1",
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

Write-Output "桌面 EXE 已生成：$outputPath"


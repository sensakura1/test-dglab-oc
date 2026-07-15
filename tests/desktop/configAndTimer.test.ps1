$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$desktopScript = Join-Path $projectRoot "src\desktop\OCWritingFocusApp.Wpf.ps1"
$previousSelfTest = $env:OC_WRITING_FOCUS_SELF_TEST
try {
  $env:OC_WRITING_FOCUS_SELF_TEST = "1"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $desktopScript
  if ($LASTEXITCODE -ne 0) {
    throw "桌面配置与 Socket 到期测试失败，退出码：$LASTEXITCODE"
  }
} finally {
  $env:OC_WRITING_FOCUS_SELF_TEST = $previousSelfTest
}

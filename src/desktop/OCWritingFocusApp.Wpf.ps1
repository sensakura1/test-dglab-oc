$ErrorActionPreference = "Stop"

$script:DesktopSourceRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
  $PSScriptRoot
} else {
  $env:OC_WRITING_FOCUS_DESKTOP_ROOT
}
if ([string]::IsNullOrWhiteSpace($script:DesktopSourceRoot)) {
  throw "Unable to resolve the desktop script directory."
}
$script:DesktopSourceRoot = [IO.Path]::GetFullPath($script:DesktopSourceRoot)

$desktopParts = @(
  "00-runtime-types.ps1",
  "10-window-view.ps1",
  "11-window-state.ps1",
  "20-ui-helpers.ps1",
  "21-configuration.ps1",
  "30-window-focus.ps1",
  "35-trigger-profile.ps1",
  "40-ble-device.ps1",
  "50-socket-device.ps1",
  "60-device-trigger.ps1",
  "65-self-test.ps1",
  "70-events-runtime.ps1"
)
foreach ($partName in $desktopParts) {
  $partPath = Join-Path $script:DesktopSourceRoot (Join-Path "parts" $partName)
  if (-not (Test-Path -LiteralPath $partPath -PathType Leaf)) {
    throw "Missing desktop script part: $partPath"
  }
  . $partPath
}

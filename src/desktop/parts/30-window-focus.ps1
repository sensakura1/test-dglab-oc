function Show-AppPage([string]$PageName) {
  $collapsed = [Windows.Visibility]::Collapsed
  $visible = [Windows.Visibility]::Visible
  $DashboardPage.Visibility = $collapsed
  $SettingsPage.Visibility = $collapsed
  $SessionControlPanel.Visibility = $collapsed
  $TriggerStrategyPanel.Visibility = $collapsed
  $CoyoteOutputPanel.Visibility = $collapsed
  $DeviceSafetyPanel.Visibility = $collapsed
  $LowerPages.Visibility = $collapsed
  $ScopeRulesPanel.Visibility = $collapsed
  $LogsPanel.Visibility = $collapsed

  $navButtons = @($NavDashboardButton, $NavScopeButton, $NavTriggerButton, $NavDeviceButton, $NavLogsButton)
  foreach ($button in $navButtons) {
    $button.Background = [Windows.Media.Brushes]::Transparent
  }

  switch ($PageName) {
    "scope" {
      $LowerPages.Visibility = $visible
      $ScopeRulesPanel.Visibility = $visible
      [Windows.Controls.Grid]::SetColumn($ScopeRulesPanel, 0)
      [Windows.Controls.Grid]::SetColumnSpan($ScopeRulesPanel, 2)
      $PageEyebrowValue.Text = "FOCUS SESSION  /  SCOPE RULES"
      $PageTitleValue.Text = "范围规则"
      $activeButton = $NavScopeButton
      Refresh-WindowPicker
    }
    "trigger" {
      $SettingsPage.Visibility = $visible
      $SessionControlPanel.Visibility = $visible
      $TriggerStrategyPanel.Visibility = $visible
      $CoyoteOutputPanel.Visibility = $visible
      $PageEyebrowValue.Text = "FOCUS SESSION  /  TRIGGER PROFILE"
      $PageTitleValue.Text = "触发设置"
      $activeButton = $NavTriggerButton
    }
    "device" {
      $SettingsPage.Visibility = $visible
      $DeviceSafetyPanel.Visibility = $visible
      $PageEyebrowValue.Text = "FOCUS SESSION  /  DEVICE SAFETY"
      $PageTitleValue.Text = "设备与安全"
      $activeButton = $NavDeviceButton
    }
    "logs" {
      $LowerPages.Visibility = $visible
      $LogsPanel.Visibility = $visible
      [Windows.Controls.Grid]::SetColumn($LogsPanel, 0)
      [Windows.Controls.Grid]::SetColumnSpan($LogsPanel, 2)
      $PageEyebrowValue.Text = "FOCUS SESSION  /  EVENT LOG"
      $PageTitleValue.Text = "日志"
      $activeButton = $NavLogsButton
    }
    default {
      $DashboardPage.Visibility = $visible
      $PageEyebrowValue.Text = "FOCUS SESSION  /  DASHBOARD"
      $PageTitleValue.Text = "控制台"
      $activeButton = $NavDashboardButton
    }
  }

  $activeButton.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(45, 140, 255))
  $MainScrollViewer.ScrollToTop()
}

function Initialize-ScopeLists {
  $WhitelistList.Items.Clear()
  $BlacklistList.Items.Clear()
}

function Test-WindowRuleList($Text, $ListBox) {
  foreach ($item in $ListBox.Items) {
    $rule = [string]$item
    if (-not [string]::IsNullOrWhiteSpace($rule) -and $Text -eq $rule) {
      return $rule
    }
  }
  return $null
}

function Get-ForegroundWindowInfo {
  try {
    $handle = [NativeWindowApi]::GetForegroundWindow()
    if ($handle -eq [IntPtr]::Zero) {
      return @{
        Process = "unknown"
        Title = ""
        Display = "unknown"
      }
    }

    $builder = New-Object System.Text.StringBuilder 512
    [void][NativeWindowApi]::GetWindowText($handle, $builder, $builder.Capacity)

    [uint32]$processId = 0
    [void][NativeWindowApi]::GetWindowThreadProcessId($handle, [ref]$processId)
    $processName = "unknown"
    try {
      $process = Get-Process -Id $processId -ErrorAction Stop
      $processName = $process.ProcessName
    } catch {
      $processName = "pid:$processId"
    }

    $title = $builder.ToString()
    return @{
      Process = $processName
      Title = $title
      Display = "$processName | $title"
    }
  } catch {
    return @{
      Process = "unknown"
      Title = ""
      Display = "读取当前窗口失败：$($_.Exception.Message)"
    }
  }
}

function Get-WindowInfoFromHandle([IntPtr]$Handle) {
  $builder = New-Object System.Text.StringBuilder 512
  [void][NativeWindowApi]::GetWindowText($Handle, $builder, $builder.Capacity)
  $title = $builder.ToString().Trim()
  if ([string]::IsNullOrWhiteSpace($title)) {
    return $null
  }

  [uint32]$processId = 0
  [void][NativeWindowApi]::GetWindowThreadProcessId($Handle, [ref]$processId)
  $processName = "unknown"
  try {
    $process = Get-Process -Id $processId -ErrorAction Stop
    $processName = $process.ProcessName
  } catch {
    $processName = "pid:$processId"
  }

  return "$processName | $title"
}

function Refresh-WindowPicker {
  $WindowPickerCombo.Items.Clear()
  $seen = New-Object 'System.Collections.Generic.HashSet[string]'
  $callback = [NativeWindowApi+EnumWindowsProc]{
    param([IntPtr]$hWnd, [IntPtr]$lParam)
    if (-not [NativeWindowApi]::IsWindowVisible($hWnd)) {
      return $true
    }
    $display = Get-WindowInfoFromHandle $hWnd
    if ($null -ne $display -and $seen.Add($display)) {
      [void]$WindowPickerCombo.Items.Add($display)
    }
    return $true
  }
  [void][NativeWindowApi]::EnumWindows($callback, [IntPtr]::Zero)
  if ($WindowPickerCombo.Items.Count -gt 0) {
    $WindowPickerCombo.SelectedIndex = 0
  }
  Add-Log "已刷新窗口列表：$($WindowPickerCombo.Items.Count) 个窗口"
}

function Refresh-CurrentWindow {
  $info = Get-ForegroundWindowInfo
  $CurrentWindowInput.Text = $info.Display
  $display = ([string]$info.Display).Trim()
  if ([string]::IsNullOrWhiteSpace($display) -or $display -eq "unknown") {
    $CurrentWindowMatchValue.Text = "无法识别"
  } elseif ($null -ne (Test-WindowRuleList $display $BlacklistList)) {
    $CurrentWindowMatchValue.Text = "黑名单"
  } elseif ($null -ne (Test-WindowRuleList $display $WhitelistList)) {
    $CurrentWindowMatchValue.Text = "白名单"
  } else {
    $CurrentWindowMatchValue.Text = "未匹配"
  }
  return $info.Display
}

function Apply-CurrentWindowRule($CurrentWindowInfo = $null) {
  if ($null -eq $CurrentWindowInfo) {
    $CurrentWindowInfo = Refresh-CurrentWindow
  }
  $text = ([string]$CurrentWindowInfo).Trim()
  $windowChanged = $script:State.LastWindowKey -ne $text
  if ($windowChanged) {
    $script:State.LastWindowKey = $text
  }
  if ([string]::IsNullOrWhiteSpace($text)) {
    $script:State.WindowState = "left"
    if (-not $script:State.AwayEpisodeActive) {
      $script:State.AwayEpisodeActive = $true
      $script:State.EpisodeTriggerSent = $false
    }
    if ($windowChanged) { Add-Log "当前窗口为空：按未命中处理" }
    return
  }

  $black = Test-WindowRuleList $text $BlacklistList
  if ($null -ne $black) {
    $script:State.WindowState = "blacklist"
    $script:State.LeftSeconds = 0
    $script:State.DistractionSeconds = 0
    if ($windowChanged) { Add-Log "黑名单命中：$black" }
    if (-not $script:State.AwayEpisodeActive) {
      $script:State.AwayEpisodeActive = $true
      $script:State.EpisodeTriggerSent = $false
    }
    if (-not $script:State.EpisodeTriggerSent -and $script:State.Connected) {
      if (Invoke-Trigger "黑名单直接触发") {
        $script:State.EpisodeTriggerSent = $true
      }
    }
    return
  }

  $white = Test-WindowRuleList $text $WhitelistList
  if ($null -ne $white) {
    if ($script:State.OutputActive -and $script:State.OutputHoldUntilWhitelist) {
      Invoke-DeviceStop
    }
    $script:State.WindowState = "writing"
    $script:State.HoldRetriggerPending = $false
    $script:State.HoldCooldownEnd = [DateTime]::MinValue
    $script:State.LeftSeconds = 0
    $script:State.DistractionSeconds = 0
    $script:State.AwayEpisodeActive = $false
    $script:State.EpisodeTriggerSent = $false
    if ($windowChanged) { Add-Log "白名单命中：$white，不处罚" }
    return
  }

  $script:State.WindowState = "left"
  if (-not $script:State.AwayEpisodeActive) {
    $script:State.AwayEpisodeActive = $true
    $script:State.EpisodeTriggerSent = $false
  }
  if ($windowChanged) { Add-Log "未命中黑白名单：按常规离开时间规则处理" }
}

function Get-StatusText {
  if ($script:State.Locked) { return "急停锁定" }
  if (-not $script:State.Running) { return "未开始" }
  if ($script:State.Paused) { return "已暂停" }
  switch ($script:State.WindowState) {
    "writing" { return "写作中" }
    "left" { return "离开中" }
    "blacklist" { return "黑名单命中" }
    "ignore" { return "忽略中" }
    default { return "未知" }
  }
}

function Update-View {
  $StatusValue.Text = Get-StatusText
  $SessionValue.Text = Format-Seconds $script:State.SessionSeconds
  $LeftValue.Text = Format-Seconds $script:State.LeftSeconds
  $DistractionValue.Text = Format-Seconds $script:State.DistractionSeconds
  $IdleValue.Text = Format-Seconds $script:State.IdleSeconds
  if ($script:State.ActualStrengthKnown) {
    $ActualStrengthValue.Text = "A $($script:State.ActualStrengthA)  |  B $($script:State.ActualStrengthB)"
  } else {
    $ActualStrengthValue.Text = "A --  |  B --"
  }
  $ActualStrengthSource.Text = $script:State.ActualStrengthSource
  $socketWaveformManaged = $script:State.DeviceMode -eq "socket"
  $StrengthARangeInput.IsReadOnly = $false
  $StrengthBRangeInput.IsReadOnly = $false
  $ChannelModeCombo.IsEnabled = $true
  $WaveformCombo.IsEnabled = $false
  $CurrentWaveformText.Text = if ($socketWaveformManaged) { "App 当前波形（协议未提供具体名称）" } else { "不支持" }
  $WavePeriodInput.IsReadOnly = $socketWaveformManaged
  $WaveIntensityInput.IsReadOnly = $socketWaveformManaged
  $SocketOutputModeText.Visibility = if ($socketWaveformManaged) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
  if ($socketWaveformManaged) {
    $SocketOutputModeText.Text = if ($script:State.SocketHasAppLimits) {
      "Socket：强度和持续时间使用本软件设置；波形由 App 决定。App 安全上限 A=$($script:State.SocketAppLimitA)，B=$($script:State.SocketAppLimitB)"
    } else {
      "Socket：强度和持续时间使用本软件设置；波形由 App 决定。等待 App 上报安全上限，收到前禁止输出"
    }
  }
  Update-FloatingMonitor
  if ($script:State.DeviceMode -eq "http") {
    $DeviceValue.Text = if ($script:State.Connected) { "真实桥接已连接" } else { "真实桥接未连接" }
    $DeviceBadge.Text = if ($script:State.Connected) { "真实设备桥接" } else { "真实桥接未连接" }
  } elseif ($script:State.DeviceMode -eq "ble") {
    $DeviceValue.Text = if ($script:State.Connected) { "蓝牙设备已连接" } else { "蓝牙设备未连接" }
    $DeviceBadge.Text = if ($script:State.Connected) { "蓝牙 V3 直连" } else { "蓝牙未连接" }
  } elseif ($script:State.DeviceMode -eq "socket") {
    $registered = -not [string]::IsNullOrWhiteSpace($script:State.SocketClientId)
    $DeviceValue.Text = if ($script:State.Connected) { "Socket App 已绑定" } elseif ($registered) { "等待 App 绑定" } else { "Socket 未连接" }
    $DeviceBadge.Text = if ($script:State.Connected) { "Socket 控制协议" } elseif ($registered) { "Socket 已注册" } else { "Socket 未连接" }
  }
  $LockBadge.Text = if ($script:State.Locked) { "已锁定" } else { "未锁定" }
  $UnlockButton.IsEnabled = $script:State.Locked

  if ($script:State.Locked) {
    $LockBadge.Foreground = [Windows.Media.Brushes]::White
    $LockBadgeBorder.Background = [Windows.Media.Brushes]::IndianRed
  } else {
    $LockBadge.Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(102, 179, 255))
    $LockBadgeBorder.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(37, 56, 74))
  }
}


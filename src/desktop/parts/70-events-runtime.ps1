$NavDashboardButton.Add_Click({ Show-AppPage "dashboard" })
$NavScopeButton.Add_Click({ Show-AppPage "scope" })
$NavTriggerButton.Add_Click({ Show-AppPage "trigger" })
$NavDeviceButton.Add_Click({ Show-AppPage "device" })
$NavLogsButton.Add_Click({ Show-AppPage "logs" })

$StartButton.Add_Click({
  if ($script:State.OutputActive) { Invoke-DeviceStop | Out-Null }
  $focusMinutes = Get-IntText $FocusMinutesInput 45
  if ($focusMinutes -lt 1 -or $focusMinutes -gt 10080) {
    $focusMinutes = 45
    $FocusMinutesInput.Text = "45"
    Add-Log "专注时长需为 1 至 10080 分钟，已恢复为 45 分钟"
  }
  $script:State.Running = $true
  $script:State.Paused = $false
  $script:State.SessionSeconds = $focusMinutes * 60
  $script:State.LeftSeconds = 0
  $script:State.DistractionSeconds = 0
  $script:State.IdleSeconds = 0
  $script:State.IdleTriggerSent = $false
  $script:State.FocusStartedAt = Get-Date
  $script:State.AwayEpisodeActive = $false
  $script:State.EpisodeTriggerSent = $false
  Add-Log "专注周期已开始：$focusMinutes 分钟"
  Update-View
})

$PauseButton.Add_Click({
  if ($script:State.Running) {
    $script:State.Paused = -not $script:State.Paused
    if ($script:State.Paused) {
      if ($script:State.OutputActive) { Invoke-DeviceStop | Out-Null }
      Add-Log "专注已暂停，活动输出已停止"
    } else {
      $script:State.IdleSeconds = 0
      $script:State.IdleTriggerSent = $false
      $script:State.FocusStartedAt = Get-Date
      Add-Log "专注已恢复"
    }
    Update-View
  }
})

$EndButton.Add_Click({
  if ($script:State.OutputActive) { Invoke-DeviceStop | Out-Null }
  $script:State.Running = $false
  $script:State.Paused = $false
  $script:State.LeftSeconds = 0
  $script:State.DistractionSeconds = 0
  $script:State.IdleSeconds = 0
  $script:State.IdleTriggerSent = $false
  $script:State.FocusStartedAt = [DateTime]::MinValue
  $script:State.AwayEpisodeActive = $false
  $script:State.EpisodeTriggerSent = $false
  Add-Log "专注周期已结束"
  Update-View
})

$EmergencyButton.Add_Click({
  if ($script:State.Connected) { Invoke-DeviceStop | Out-Null }
  $script:State.Locked = $true
  Add-Log "急停已执行，设备输出停止"
  Update-View
})

$UnlockButton.Add_Click({
  $script:State.Locked = $false
  Add-Log "安全锁定已解除"
  Update-View
})

$ManualTestButton.Add_Click({ Invoke-Trigger "手动测试" })
$FloatingMonitorButton.Add_Click({ Toggle-FloatingMonitor })
$SocketServerModeCombo.Add_SelectionChanged({
  if ($null -ne $script:State.SocketClient -or $null -ne $script:State.LocalSocketServer) { Reset-SocketConnection }
  if ($SocketServerModeCombo.SelectedIndex -eq 0) {
    $script:State.SocketServerMode = "local"
    $LocalSocketSettings.Visibility = [Windows.Visibility]::Visible
    $RemoteSocketSettings.Visibility = [Windows.Visibility]::Collapsed
    $ConnectButton.Content = "启动本地服务器并生成二维码"
    Add-Log "Socket 已切换到本地服务器模式"
  } else {
    $script:State.SocketServerMode = "remote"
    $LocalSocketSettings.Visibility = [Windows.Visibility]::Collapsed
    $RemoteSocketSettings.Visibility = [Windows.Visibility]::Visible
    $ConnectButton.Content = "连接外部服务器并生成二维码"
    Add-Log "Socket 已切换到外部服务器模式"
  }
  Update-View
})
$DeviceModeCombo.Add_SelectionChanged({
  if ($script:State.OutputActive -and $script:State.Connected) { Invoke-DeviceStop | Out-Null }
  if ($null -ne $script:State.SocketClient -or $null -ne $script:State.LocalSocketServer) { Reset-SocketConnection }
  Set-ActualStrengthState 0 0 "设备模式已切换，等待连接" $false
  $HttpConnectionPage.Visibility = [Windows.Visibility]::Collapsed
  $BleConnectionPage.Visibility = [Windows.Visibility]::Collapsed
  $SocketConnectionPage.Visibility = [Windows.Visibility]::Collapsed
  if ($DeviceModeCombo.SelectedIndex -eq 2) {
    $script:State.DeviceMode = "socket"
    $script:State.Connected = $false
    $SocketConnectionPage.Visibility = [Windows.Visibility]::Visible
    $ConnectButton.Content = if ($script:State.SocketServerMode -eq "local") { "启动本地服务器并生成二维码" } else { "连接外部服务器并生成二维码" }
    $ApplySafetyButton.Visibility = [Windows.Visibility]::Collapsed
    Add-Log "已切换到 Socket 控制协议模式"
  } elseif ($DeviceModeCombo.SelectedIndex -eq 1) {
    $script:State.DeviceMode = "ble"
    $script:State.Connected = $false
    $BleConnectionPage.Visibility = [Windows.Visibility]::Visible
    $ConnectButton.Content = "连接并应用安全参数"
    $ApplySafetyButton.Visibility = [Windows.Visibility]::Visible
    Add-Log "已切换到蓝牙 V3 直连模式"
  } else {
    $script:State.DeviceMode = "http"
    $script:State.Connected = $false
    $HttpConnectionPage.Visibility = [Windows.Visibility]::Visible
    $ConnectButton.Content = "连接 HTTP 桥接"
    $ApplySafetyButton.Visibility = [Windows.Visibility]::Collapsed
    Add-Log "已切换到 HTTP 真实设备桥接模式"
  }
  Update-View
})
$ConnectButton.Add_Click({ Invoke-DeviceStatus; Update-View })
$ApplySafetyButton.Add_Click({ Apply-BleSafetySettings | Out-Null; Update-View })
$DisconnectButton.Add_Click({
  if ($script:State.Connected) { Invoke-DeviceStop | Out-Null }
  if ($null -ne $script:State.SocketClient -or $null -ne $script:State.LocalSocketServer) { Reset-SocketConnection }
  $script:State.Connected = $false
  $script:Ble.WriteCharacteristic = $null
  $script:Ble.Service = $null
  $script:Ble.Device = $null
  Set-ActualStrengthState 0 0 "设备已断开" $false
  Add-Log "设备连接已断开"
  Update-View
})
$StopButton.Add_Click({ Invoke-DeviceStop; Update-View })
$ClearLogsButton.Add_Click({ $LogList.Items.Clear() })
$ImportConfigButton.Add_Click({ Import-DesktopConfiguration })
$ExportConfigButton.Add_Click({
  try { Export-DesktopConfiguration }
  catch {
    Add-Log "配置导出失败：$($_.Exception.Message)"
    [Windows.MessageBox]::Show("配置导出失败：`r`n`r`n$($_.Exception.Message)", "导出配置", "OK", "Error") | Out-Null
  }
})
$ResetSafeConfigButton.Add_Click({ Reset-SafeDesktopConfiguration })

$RefreshWindowListButton.Add_Click({
  Refresh-WindowPicker
})

$AddWhitelistButton.Add_Click({
  $value = [string]$WindowPickerCombo.SelectedItem
  if (-not [string]::IsNullOrWhiteSpace($value)) {
    if (-not $WhitelistList.Items.Contains($value)) {
      [void]$WhitelistList.Items.Add($value)
      Add-Log "已添加窗口白名单：$value"
    }
  }
  Refresh-CurrentWindow | Out-Null
  Update-View
})

$RemoveWhitelistButton.Add_Click({
  if ($WhitelistList.SelectedIndex -ge 0) {
    $value = [string]$WhitelistList.SelectedItem
    $WhitelistList.Items.RemoveAt($WhitelistList.SelectedIndex)
    Add-Log "已删除白名单：$value"
  }
  Refresh-CurrentWindow | Out-Null
})

$AddBlacklistButton.Add_Click({
  $value = [string]$WindowPickerCombo.SelectedItem
  if (-not [string]::IsNullOrWhiteSpace($value)) {
    if (-not $BlacklistList.Items.Contains($value)) {
      [void]$BlacklistList.Items.Add($value)
      Add-Log "已添加窗口黑名单：$value"
    }
  }
  Refresh-CurrentWindow | Out-Null
  Update-View
})

$RemoveBlacklistButton.Add_Click({
  if ($BlacklistList.SelectedIndex -ge 0) {
    $value = [string]$BlacklistList.SelectedItem
    $BlacklistList.Items.RemoveAt($BlacklistList.SelectedIndex)
    Add-Log "已删除黑名单：$value"
  }
  Refresh-CurrentWindow | Out-Null
})

function Update-OutputExpiration {
  if (-not $script:State.OutputActive -or (Get-Date) -lt $script:State.OutputEnd) {
    return
  }
  $wasHoldMode = $script:State.OutputHoldUntilWhitelist
  $expiredProfile = $script:State.OutputProfile
  Invoke-DeviceStop | Out-Null
  if ($wasHoldMode -and $null -ne $expiredProfile -and $script:State.WindowState -in @("left", "blacklist")) {
    $script:State.HoldRetriggerPending = $true
    $script:State.HoldCooldownEnd = (Get-Date).AddMilliseconds($expiredProfile.CooldownMs)
    Add-Log "已达到最长连续输出时间并停止；进入 $([int]($expiredProfile.CooldownMs / 1000)) 秒冷却期"
  }
}

function Update-HoldCooldown {
  if (-not $script:State.HoldRetriggerPending) { return }
  if ($script:State.WindowState -eq "writing" -or -not $script:State.Running -or $script:State.Paused -or $script:State.Locked) {
    $script:State.HoldRetriggerPending = $false
    $script:State.HoldCooldownEnd = [DateTime]::MinValue
    return
  }
  if ((Get-Date) -lt $script:State.HoldCooldownEnd) { return }
  if ($script:State.WindowState -notin @("left", "blacklist") -or -not $script:State.Connected) {
    $script:State.HoldCooldownEnd = (Get-Date).AddSeconds(5)
    return
  }
  $script:State.HoldRetriggerPending = $false
  if (-not (Invoke-Trigger "冷却结束仍未返回白名单")) {
    $script:State.HoldRetriggerPending = $true
    $script:State.HoldCooldownEnd = (Get-Date).AddSeconds(5)
  }
}

$bleOutputTimer = New-Object Windows.Threading.DispatcherTimer
$bleOutputTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$bleOutputTimer.Add_Tick({
  if (-not $script:Ble.OutputActive) { return }
  Update-OutputExpiration
  if (-not $script:Ble.OutputActive) { return }
  if (-not $script:State.Connected -or $script:State.Locked) {
    Invoke-DeviceStop | Out-Null
    return
  }
  try {
    Invoke-BleWrite (New-DglabB0Packet $script:Ble.OutputProfile)
  } catch {
    Add-Log "蓝牙连续波形发送失败：$($_.Exception.Message)"
    $script:State.Connected = $false
    $script:Ble.OutputActive = $false
    $script:State.OutputActive = $false
  }
})
$bleOutputTimer.Start()

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
  if ($script:State.DeviceMode -eq "socket") {
    if ($null -ne $script:State.LocalSocketServer) { Update-LocalSocketServer } else { Update-SocketReceive }
    Update-SocketSafetyWatchdogStatus
  }
  # 当前前台窗口展示与专注会话解耦，任何状态下都保持实时更新。
  $currentWindowInfo = Refresh-CurrentWindow
  if ($script:State.Running -and -not $script:State.Paused -and -not $script:State.Locked) {
    Apply-CurrentWindowRule $currentWindowInfo
    if ($script:State.SessionSeconds -gt 0) { $script:State.SessionSeconds -= 1 }
    $previousIdleSeconds = $script:State.IdleSeconds
    $systemIdleSeconds = Get-SystemIdleSeconds
    $sessionAgeSeconds = [int][Math]::Floor(((Get-Date) - $script:State.FocusStartedAt).TotalSeconds)
    $script:State.IdleSeconds = [Math]::Max(0, [Math]::Min($systemIdleSeconds, $sessionAgeSeconds))
    if ($script:State.IdleSeconds -lt $previousIdleSeconds) {
      $script:State.IdleTriggerSent = $false
    }

    switch ($script:State.WindowState) {
      "writing" {
        $script:State.LeftSeconds = 0
        $script:State.DistractionSeconds = 0
      }
      "left" {
        $script:State.LeftSeconds += 1
        $script:State.DistractionSeconds = 0
      }
      "blacklist" {
        $script:State.LeftSeconds = 0
        $script:State.DistractionSeconds = 0
      }
      "ignore" {
        $script:State.LeftSeconds = 0
        $script:State.DistractionSeconds = 0
      }
    }

    $leaveSeconds = Get-IntText $LeaveInput 300
    if ($script:State.AwayEpisodeActive -and -not $script:State.EpisodeTriggerSent -and $script:State.WindowState -eq "left" -and $script:State.LeftSeconds -ge $leaveSeconds -and $script:State.Connected) {
      if (Invoke-Trigger "离开写作范围") {
        $script:State.EpisodeTriggerSent = $true
      }
    }
    $idleTriggerSeconds = Get-ClampedInt $IdleInput 600 1 86400
    if (-not $script:State.IdleTriggerSent -and $script:State.IdleSeconds -ge $idleTriggerSeconds -and $script:State.Connected) {
      if (Invoke-Trigger "长时间无输入") {
        $script:State.IdleTriggerSent = $true
      }
    }
    if ($script:State.SessionSeconds -eq 0) {
      Invoke-Trigger "专注周期结束"
      $script:State.Running = $false
      $script:State.Paused = $false
      Add-Log "专注周期计时完成"
    }
  }

  Update-OutputExpiration
  Update-HoldCooldown
  Update-View
})

$floatingMonitorTimer = New-Object Windows.Threading.DispatcherTimer
$floatingMonitorTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$floatingMonitorTimer.Add_Tick({ Update-FloatingMonitor })

$window.Add_Closing({
  $timer.Stop()
  $bleOutputTimer.Stop()
  $floatingMonitorTimer.Stop()
  if ($null -ne $script:FloatingMonitorWindow) {
    $script:FloatingMonitorWindow.Close()
  }
  if ($script:State.Connected) {
    Invoke-DeviceStop | Out-Null
  }
  if ($null -ne $script:State.SocketClient -or $null -ne $script:State.LocalSocketServer) { Reset-SocketConnection }
})

$timer.Start()
$floatingMonitorTimer.Start()
$LocalSocketHostInput.Text = Get-PreferredLocalIpv4Address
Initialize-ScopeLists
Show-AppPage "dashboard"
Refresh-CurrentWindow | Out-Null
Refresh-WindowPicker
Add-Log "桌面应用已启动"
Update-View
if ($env:OC_WRITING_FOCUS_SELF_TEST -eq "1") {
  Invoke-DesktopSelfTest
  return
}
[void]$window.ShowDialog()

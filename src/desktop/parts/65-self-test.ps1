function Invoke-DesktopSelfTest {
  $timer.Stop()
  $bleOutputTimer.Stop()
  $floatingMonitorTimer.Stop()
  foreach ($allowedEndpoint in @(
    @{ Text = "https://device.example.com"; Kind = "http" },
    @{ Text = "http://127.0.0.1:8080"; Kind = "http" },
    @{ Text = "http://192.168.1.20:8080"; Kind = "http" },
    @{ Text = "wss://socket.example.com"; Kind = "socket" },
    @{ Text = "ws://10.0.0.20:5678"; Kind = "socket" }
  )) {
    [void](Assert-SecureNetworkEndpoint $allowedEndpoint.Text $allowedEndpoint.Kind)
  }
  foreach ($rejectedEndpoint in @(
    @{ Text = "http://example.com"; Kind = "http" },
    @{ Text = "ws://8.8.8.8:5678"; Kind = "socket" },
    @{ Text = "http://user:password@127.0.0.1:8080"; Kind = "http" },
    @{ Text = "wss://socket.example.com/connect?token=secret"; Kind = "socket" }
  )) {
    $endpointRejected = $false
    try { [void](Assert-SecureNetworkEndpoint $rejectedEndpoint.Text $rejectedEndpoint.Kind) } catch { $endpointRejected = $true }
    if (-not $endpointRejected) { throw "不安全网络地址未被拒绝：$($rejectedEndpoint.Text)" }
  }
  Set-DesktopConfiguration (Get-SafeDesktopConfiguration) "自动测试安全默认值"
  $roundTrip = ((Get-DesktopConfiguration) | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
  Set-DesktopConfiguration $roundTrip "自动测试往返配置"
  if ($roundTrip.schemaVersion -ne 2 -or $roundTrip.trigger.outputMode -ne "fixedDuration" -or $roundTrip.trigger.durationSeconds -ne 1) {
    throw "配置 JSON 往返测试失败"
  }
  if ($StrengthARangeInput.Text -ne "10-20" -or $SoftLimitAInput.Text -ne "30" -or $HttpLimitAInput.Text -ne "30" -or $DurationInput.Text -ne "1" -or $MaxContinuousInput.Text -ne "10" -or $HoldCooldownInput.Text -ne "60") {
    throw "安全默认值应用测试失败"
  }
  $legacyConfig = ($roundTrip | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
  $legacyConfig.schemaVersion = 1
  $legacyConfig.trigger | Add-Member -NotePropertyName durationMs -NotePropertyValue 1500
  $legacyConfig.trigger.PSObject.Properties.Remove("durationSeconds")
  Set-DesktopConfiguration $legacyConfig "自动测试旧版配置"
  if ($DurationInput.Text -ne "2" -or (Get-TriggerProfile).DurationMs -ne 2000) {
    throw "旧版毫秒配置转换或秒到毫秒内部换算失败"
  }
  $invalidRejected = $false
  try {
    $roundTrip.trigger.durationSeconds = 999999
    Set-DesktopConfiguration $roundTrip "无效配置"
  } catch {
    $invalidRejected = $true
  }
  if (-not $invalidRejected) { throw "无效配置未被拒绝" }
  Set-ActualStrengthState 17 23 "自动测试"
  if ($ActualStrengthValue.Text -ne "A 17  |  B 23" -or $ActualStrengthSource.Text -ne "自动测试") { throw "A/B 实际强度显示测试失败" }
  $script:FloatingMonitorWindow = New-FloatingMonitorWindow
  Update-FloatingMonitor
  if ($script:FloatingStrengthAValue.Text -ne "17" -or $script:FloatingStrengthBValue.Text -ne "23" -or $script:FloatingDurationValue.Text -ne "本次持续：2 秒" -or $script:FloatingRemainingValue.Text -ne "剩余时间：未输出") {
    throw "悬浮监控窗口内容测试失败"
  }
  $script:State.OutputActive = $true
  $script:State.OutputHoldUntilWhitelist = $false
  $script:State.OutputProfile = @{ DurationMs = 3000 }
  $script:State.OutputEnd = (Get-Date).AddSeconds(2.5)
  Update-FloatingMonitor
  if ($script:FloatingDurationValue.Text -ne "本次持续：3 秒" -or $script:FloatingRemainingValue.Text -notmatch '^剩余时间：[0-9]+\.[0-9] 秒$') {
    throw "悬浮监控单次持续或剩余时间测试失败"
  }
  $script:State.OutputActive = $false
  $script:State.OutputProfile = $null
  $script:State.OutputEnd = [DateTime]::MinValue
  $script:FloatingMonitorWindow.Close()
  $profileLimitTest = @{ AStrength = 90; BStrength = 70 }
  $script:State.DeviceMode = "http"
  $HttpLimitAInput.Text = "20"; $HttpLimitBInput.Text = "30"
  $profileLimitTest = Limit-TriggerProfile $profileLimitTest
  if ($profileLimitTest.AStrength -ne 20 -or $profileLimitTest.BStrength -ne 30) { throw "HTTP 手动上限截断失败" }
  $script:State.DeviceMode = "socket"
  $script:State.SocketHasAppLimits = $false
  $socketUnknownBlocked = $false
  try { Limit-TriggerProfile @{ AStrength = 10; BStrength = 10 } | Out-Null } catch { $socketUnknownBlocked = $true }
  if (-not $socketUnknownBlocked) { throw "Socket 未获 App 上限时没有禁止输出" }
  $StrengthARangeInput.Text = "12-12"
  $StrengthBRangeInput.Text = "14-14"
  $ChannelModeCombo.SelectedIndex = 0
  Set-SocketAppStrengthState 5 6 15 18
  if ($StrengthARangeInput.Text -ne "12-12" -or $StrengthBRangeInput.Text -ne "14-14" -or $StrengthARangeInput.IsReadOnly -or $StrengthBRangeInput.IsReadOnly -or -not $ChannelModeCombo.IsEnabled) {
    throw "Socket App 上报错误覆盖了本软件强度或通道配置"
  }
  if ($WaveformCombo.IsEnabled -or -not $WavePeriodInput.IsReadOnly -or -not $WaveIntensityInput.IsReadOnly -or -not $DurationInput.IsEnabled) {
    throw "Socket 模式未正确禁用桌面波形设置或错误禁用了持续时间"
  }
  if ($CurrentWaveformText.Text -ne "App 当前波形（协议未提供具体名称）") {
    throw "Socket 当前波形状态未按协议能力显示"
  }
  foreach ($mode in @("http", "ble")) {
    $script:State.DeviceMode = $mode
    Update-View
    if ($CurrentWaveformText.Text -ne "不支持") {
      throw "$mode 模式错误显示了可读取的当前波形"
    }
  }
  $script:State.DeviceMode = "socket"
  Update-View
  $profileLimitTest = Limit-TriggerProfile (Get-TriggerProfile)
  if ($profileLimitTest.AStrength -ne 12 -or $profileLimitTest.BStrength -ne 14 -or $profileLimitTest.WaveformName -ne "DG-Lab App" -or $null -ne $profileLimitTest.Waveform) {
    throw "Socket 触发未使用本软件强度或未将波形交由 App 决定"
  }
  $script:SocketStopCalledByTimer = $false
  function Invoke-DeviceStop {
    $script:SocketStopCalledByTimer = $true
    $script:State.OutputActive = $false
    $script:State.OutputHoldUntilWhitelist = $false
    $script:State.OutputProfile = $null
    $script:State.OutputEnd = [DateTime]::MinValue
    $script:State.HoldRetriggerPending = $false
    $script:State.HoldCooldownEnd = [DateTime]::MinValue
    return $true
  }
  $script:State.DeviceMode = "socket"
  $script:State.OutputActive = $true
  $script:State.OutputHoldUntilWhitelist = $false
  $script:State.OutputEnd = (Get-Date).AddSeconds(-1)
  Update-OutputExpiration
  if (-not $script:SocketStopCalledByTimer) { throw "Socket 到期未调用停止流程" }
  $script:SocketStopCalledByTimer = $false
  $script:State.WindowState = "left"
  $script:State.OutputActive = $true
  $script:State.OutputHoldUntilWhitelist = $true
  $script:State.OutputProfile = @{ CooldownMs = 5000 }
  $script:State.OutputEnd = (Get-Date).AddSeconds(-1)
  Update-OutputExpiration
  if (-not $script:SocketStopCalledByTimer -or -not $script:State.HoldRetriggerPending) { throw "持续模式到期未停止或未进入冷却" }
  $script:HoldRetriggerTestCalled = $false
  function Invoke-Trigger($Reason) {
    if ($Reason -eq "冷却结束仍未返回白名单") { $script:HoldRetriggerTestCalled = $true; return $true }
    return $false
  }
  $script:State.Running = $true
  $script:State.Paused = $false
  $script:State.Locked = $false
  $script:State.Connected = $true
  $script:State.HoldCooldownEnd = (Get-Date).AddSeconds(-1)
  Update-HoldCooldown
  if (-not $script:HoldRetriggerTestCalled -or $script:State.HoldRetriggerPending) { throw "冷却结束后未按条件重新触发" }
  Write-Output "Desktop config, bounded hold/cooldown, and Socket expiration: OK"
  return
}

function Get-EndpointUrl($Action) {
  $baseUri = Assert-SecureNetworkEndpoint $HttpEndpointInput.Text "http"
  $base = $baseUri.AbsoluteUri.TrimEnd("/")
  if ($base -match "/(activate|stop|status)$") {
    return ($base -replace "/(activate|stop|status)$", "/$Action")
  }
  return "$base/$Action"
}

function Invoke-DeviceStatus {
  if ($script:State.DeviceMode -eq "ble") {
    Invoke-BleConnect
    return
  }
  if ($script:State.DeviceMode -eq "socket") {
    Invoke-SocketConnect
    return
  }

  try {
    $url = Get-EndpointUrl "status"
    Invoke-RestMethod -Method Get -Uri $url -TimeoutSec 5 | Out-Null
    $script:State.Connected = $true
    Add-Log "真实设备桥接已连接：$url"
  } catch {
    $script:State.Connected = $false
    Add-Log "真实设备桥接连接失败：$($_.Exception.Message)"
  }
}

function Invoke-DeviceStop {
  $script:State.OutputActive = $false
  $script:State.OutputHoldUntilWhitelist = $false
  $script:State.OutputProfile = $null
  $script:State.OutputEnd = [DateTime]::MinValue
  $script:State.HoldRetriggerPending = $false
  $script:State.HoldCooldownEnd = [DateTime]::MinValue
  $script:State.HttpRenewAt = [DateTime]::MinValue
  if ($script:State.DeviceMode -eq "ble") {
    return Invoke-BleStop
  }
  if ($script:State.DeviceMode -eq "socket") {
    return Invoke-SocketStop
  }

  try {
    $url = Get-EndpointUrl "stop"
    $body = @{ action = "stop" } | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body $body -TimeoutSec 5 | Out-Null
    Set-ActualStrengthState 0 0 "HTTP 桥接已确认接收"
    Add-Log "已发送真实设备停止指令"
    return $true
  } catch {
    Add-Log "真实设备停止失败：$($_.Exception.Message)"
    return $false
  }
}

function Invoke-HttpActivate($Profile) {
  try {
    $url = Get-EndpointUrl "activate"
    $legacyIntensity = [Math]::Max($Profile.AStrength, $Profile.BStrength)
    $duration = if ($Profile.HoldUntilWhitelist) { $Profile.MaxContinuousMs } else { $Profile.DurationMs }
    $limits = Get-EffectiveStrengthLimits
    $body = @{
      action = "activate"
      intensity = $legacyIntensity
      intensityA = $Profile.AStrength
      intensityB = $Profile.BStrength
      durationMs = $duration
      channel = $Profile.Channel
      pattern = $Profile.WaveformName
      pulseId = $Profile.WaveformName
      overrides = $Profile.RestartOnRepeat
      wavePeriodMs = $Profile.WavePeriodMs
      waveIntensity = $Profile.WaveIntensity
      softLimitA = $limits.A
      softLimitB = $limits.B
    } | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body $body -TimeoutSec 5 | Out-Null
    Set-ActualStrengthState ([int]$Profile.AStrength) ([int]$Profile.BStrength) "HTTP 桥接已确认接收"
    return $true
  } catch {
    Add-Log "真实设备触发失败：$($_.Exception.Message)"
    return $false
  }
}

function Invoke-DeviceActivate($Profile) {
  if ($script:State.DeviceMode -eq "ble") {
    return Invoke-BleActivate $Profile
  }
  if ($script:State.DeviceMode -eq "socket") {
    return Invoke-SocketActivate $Profile
  }
  return Invoke-HttpActivate $Profile
}

function Invoke-Trigger($Reason) {
  if ($script:State.Locked) {
    Add-Log "触发被拦截：安全锁定"
    return $false
  }
  if (-not $script:State.Connected) {
    Add-Log "触发被拦截：设备未连接"
    return $false
  }
  $profile = Get-TriggerProfile
  try { $profile = Limit-TriggerProfile $profile }
  catch {
    Add-Log "触发被拦截：$($_.Exception.Message)"
    return $false
  }
  if ($Reason -notin @("黑名单直接触发", "离开写作范围", "冷却结束仍未返回白名单")) {
    $profile.HoldUntilWhitelist = $false
  }
  $sent = Invoke-DeviceActivate $profile
  if (-not $sent) {
    return $false
  }

  $activeDurationMs = if ($profile.HoldUntilWhitelist) { $profile.MaxContinuousMs } else { $profile.DurationMs }
  if ($script:State.DeviceMode -eq "socket") {
    try { Arm-SocketSafetyWatchdog $activeDurationMs }
    catch {
      Add-Log "Socket 安全看门狗启动失败，已立即停止输出：$($_.Exception.Message)"
      Invoke-SocketStop | Out-Null
      return $false
    }
  }

  $script:State.OutputActive = $true
  $script:State.OutputHoldUntilWhitelist = $profile.HoldUntilWhitelist
  $script:State.OutputProfile = $profile
  $script:State.OutputEnd = (Get-Date).AddMilliseconds($activeDurationMs)
  $script:State.HoldRetriggerPending = $false
  $script:State.HoldCooldownEnd = [DateTime]::MinValue
  $script:State.HttpRenewAt = [DateTime]::MinValue

  $prefix = if ($script:State.DeviceMode -eq "ble") { "蓝牙输出" } else { "HTTP 输出" }
  $durationText = if ($profile.HoldUntilWhitelist) { "最长 $([int]($profile.MaxContinuousMs / 1000)) 秒，随后冷却 $([int]($profile.CooldownMs / 1000)) 秒" } else { "$([int]($profile.DurationMs / 1000)) 秒" }
  Add-Log "$Reason：$prefix 通道 $($profile.Channel)，A=$($profile.AStrength) B=$($profile.BStrength)，波形 $($profile.WaveformName)，$durationText"
  Update-View
  return $true
}


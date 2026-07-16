function Get-ClampedInt($TextBox, [int]$Default, [int]$Minimum, [int]$Maximum) {
  $value = Get-IntText $TextBox $Default
  return [Math]::Max($Minimum, [Math]::Min($Maximum, $value))
}

function Get-NumericRange($TextBox, [int]$DefaultMin, [int]$DefaultMax, [int]$Maximum) {
  $parts = $TextBox.Text -split "-"
  $min = $DefaultMin
  $max = $DefaultMax
  if ($parts.Count -eq 2) {
    [void][int]::TryParse($parts[0].Trim(), [ref]$min)
    [void][int]::TryParse($parts[1].Trim(), [ref]$max)
  }
  $min = [Math]::Max(0, [Math]::Min($Maximum, $min))
  $max = [Math]::Max(0, [Math]::Min($Maximum, $max))
  if ($min -gt $max) {
    $swap = $min
    $min = $max
    $max = $swap
  }
  return @($min, $max)
}

function Convert-WavePeriodToProtocol([int]$PeriodMs) {
  $period = [Math]::Max(10, [Math]::Min(1000, $PeriodMs))
  if ($period -le 100) { return [byte]$period }
  if ($period -le 600) { return [byte]([Math]::Floor(($period - 100) / 5) + 100) }
  return [byte]([Math]::Floor(($period - 600) / 10) + 200)
}

function Get-WaveformData {
  $frequency = Convert-WavePeriodToProtocol (Get-ClampedInt $WavePeriodInput 30 10 1000)
  $wave = Get-ClampedInt $WaveIntensityInput 35 0 100
  switch ($WaveformCombo.SelectedIndex) {
    1 { $levels = @( $wave, 0, $wave, 0 ) }
    2 { $levels = @( [Math]::Round($wave * 0.25), [Math]::Round($wave * 0.5), [Math]::Round($wave * 0.75), $wave ) }
    3 { $levels = @( $wave, [Math]::Round($wave * 0.35), 0, [Math]::Round($wave * 0.7) ) }
    default { $levels = @( $wave, $wave, $wave, $wave ) }
  }
  return @{
    Frequency = [byte[]]@($frequency, $frequency, $frequency, $frequency)
    Intensity = [byte[]]@($levels | ForEach-Object { [byte]$_ })
  }
}

function Get-TriggerProfile {
  $rangeA = Get-NumericRange $StrengthARangeInput 40 60 200
  $rangeB = Get-NumericRange $StrengthBRangeInput 40 60 200
  $channelIndex = $ChannelModeCombo.SelectedIndex
  $aEnabled = $channelIndex -ne 2
  $bEnabled = $channelIndex -ne 1
  $aStrength = if ($aEnabled) { Get-Random -Minimum $rangeA[0] -Maximum ($rangeA[1] + 1) } else { 0 }
  $bStrength = if ($bEnabled) { Get-Random -Minimum $rangeB[0] -Maximum ($rangeB[1] + 1) } else { 0 }
  $channelName = if ($channelIndex -eq 1) { "A" } elseif ($channelIndex -eq 2) { "B" } else { "both" }
  return @{
    AEnabled = $aEnabled
    BEnabled = $bEnabled
    AStrength = $aStrength
    BStrength = $bStrength
    Channel = $channelName
    DurationMs = (Get-ClampedInt $DurationInput 5 1 30) * 1000
    MaxContinuousMs = (Get-ClampedInt $MaxContinuousInput 10 1 30) * 1000
    CooldownMs = (Get-ClampedInt $HoldCooldownInput 60 5 3600) * 1000
    HoldUntilWhitelist = $OutputModeCombo.SelectedIndex -eq 0
    RestartOnRepeat = $OverlapModeCombo.SelectedIndex -eq 0
    WaveformName = if ($script:State.DeviceMode -eq "socket") { "DG-Lab App" } else { @("constant", "pulse", "ramp", "heartbeat")[[Math]::Max(0, [Math]::Min(3, $WaveformCombo.SelectedIndex))] }
    WavePeriodMs = Get-ClampedInt $WavePeriodInput 30 10 1000
    WaveIntensity = Get-ClampedInt $WaveIntensityInput 35 0 100
    Waveform = if ($script:State.DeviceMode -eq "socket") { $null } else { Get-WaveformData }
  }
}

function Get-BleSafetyConfig {
  return @{
    SoftLimitA = Get-ClampedInt $SoftLimitAInput 80 0 200
    SoftLimitB = Get-ClampedInt $SoftLimitBInput 80 0 200
    FrequencyBalanceA = Get-ClampedInt $FrequencyBalanceAInput 0 0 255
    FrequencyBalanceB = Get-ClampedInt $FrequencyBalanceBInput 0 0 255
    StrengthBalanceA = Get-ClampedInt $StrengthBalanceAInput 0 0 255
    StrengthBalanceB = Get-ClampedInt $StrengthBalanceBInput 0 0 255
  }
}

function Get-EffectiveStrengthLimits {
  switch ($script:State.DeviceMode) {
    "socket" {
      if (-not $script:State.SocketHasAppLimits) { throw "Socket 尚未收到 App 上报的 A/B 强度上限，已禁止输出。" }
      return @{ A = [int]$script:State.SocketAppLimitA; B = [int]$script:State.SocketAppLimitB; Source = "DG-Lab App" }
    }
    "ble" {
      $safety = Get-BleSafetyConfig
      return @{ A = [int]$safety.SoftLimitA; B = [int]$safety.SoftLimitB; Source = "蓝牙手动" }
    }
    default {
      return @{ A = Get-ClampedInt $HttpLimitAInput 80 0 200; B = Get-ClampedInt $HttpLimitBInput 80 0 200; Source = "HTTP 手动" }
    }
  }
}

function Limit-TriggerProfile($Profile) {
  $limits = Get-EffectiveStrengthLimits
  $requestedA = [int]$Profile.AStrength
  $requestedB = [int]$Profile.BStrength
  $Profile.AStrength = [Math]::Min($requestedA, [int]$limits.A)
  $Profile.BStrength = [Math]::Min($requestedB, [int]$limits.B)
  $Profile.StrengthLimitA = [int]$limits.A
  $Profile.StrengthLimitB = [int]$limits.B
  $Profile.StrengthLimitSource = [string]$limits.Source
  if ($requestedA -ne $Profile.AStrength -or $requestedB -ne $Profile.BStrength) {
    Add-Log "强度已按 $($limits.Source) 上限截断：A $requestedA→$($Profile.AStrength)，B $requestedB→$($Profile.BStrength)"
  }
  return $Profile
}


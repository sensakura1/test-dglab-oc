function Get-RequiredConfigValue($Object, [string]$Name) {
  if ($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Name) {
    throw "配置缺少字段：$Name"
  }
  return $Object.$Name
}

function ConvertTo-ConfigInt($Value, [string]$Name, [int]$Minimum, [int]$Maximum) {
  $parsed = 0
  if (-not [int]::TryParse([string]$Value, [ref]$parsed)) {
    throw "配置字段 $Name 必须是整数。"
  }
  if ($parsed -lt $Minimum -or $parsed -gt $Maximum) {
    throw "配置字段 $Name 必须在 $Minimum 至 $Maximum 之间。"
  }
  return $parsed
}

function ConvertTo-ConfigText($Value, [string]$Name, [int]$MaximumLength, [switch]$AllowEmpty) {
  $text = [string]$Value
  if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($text)) {
    throw "配置字段 $Name 不能为空。"
  }
  if ($text.Length -gt $MaximumLength) {
    throw "配置字段 $Name 超过最大长度 $MaximumLength。"
  }
  return $text.Trim()
}

function ConvertTo-ConfigChoice($Value, [string]$Name, [string[]]$Choices) {
  $text = [string]$Value
  if ($text -notin $Choices) {
    throw "配置字段 $Name 的值无效：$text"
  }
  return $text
}

function Test-TrustedPlaintextHost([Uri]$Uri) {
  if ($Uri.IsLoopback) { return $true }
  $address = $null
  if (-not [Net.IPAddress]::TryParse($Uri.DnsSafeHost, [ref]$address)) { return $false }
  $bytes = $address.GetAddressBytes()
  if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
    return $bytes[0] -eq 10 -or
      ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
      ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or
      ($bytes[0] -eq 169 -and $bytes[1] -eq 254)
  }
  if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) {
    return [Net.IPAddress]::IsLoopback($address) -or
      (($bytes[0] -band 0xFE) -eq 0xFC) -or
      ($bytes[0] -eq 0xFE -and ($bytes[1] -band 0xC0) -eq 0x80)
  }
  return $false
}

function Assert-SecureNetworkEndpoint([string]$Text, [ValidateSet("http", "socket")][string]$Kind) {
  $label = if ($Kind -eq "http") { "HTTP 桥接地址" } else { "WebSocket 服务器地址" }
  if ([string]::IsNullOrWhiteSpace($Text)) { throw "$label 不能为空。" }
  $uri = $null
  if (-not [Uri]::TryCreate($Text.Trim(), [UriKind]::Absolute, [ref]$uri) -or [string]::IsNullOrWhiteSpace($uri.Host)) {
    throw "$label 不是有效的绝对 URL。"
  }
  if (-not [string]::IsNullOrEmpty($uri.UserInfo)) { throw "$label 不允许在 URL 中携带用户名或密码。" }
  if (-not [string]::IsNullOrEmpty($uri.Fragment) -or -not [string]::IsNullOrEmpty($uri.Query)) {
    throw "$label 不允许包含查询参数或片段。"
  }
  $secureScheme = if ($Kind -eq "http") { "https" } else { "wss" }
  $plainScheme = if ($Kind -eq "http") { "http" } else { "ws" }
  if ($uri.Scheme -eq $secureScheme) { return $uri }
  if ($uri.Scheme -ne $plainScheme) {
    throw "$label 必须使用 $secureScheme`://；可信本机或局域网可使用 $plainScheme`://。"
  }
  if (-not (Test-TrustedPlaintextHost $uri)) {
    throw "$plainScheme`:// 明文连接仅允许回环、RFC1918 私有或链路本地 IP；远程地址必须使用 $secureScheme`://。"
  }
  return $uri
}

function Get-DesktopConfiguration {
  $rangeA = Get-NumericRange $StrengthARangeInput 40 60 200
  $rangeB = Get-NumericRange $StrengthBRangeInput 40 60 200
  return [ordered]@{
    schemaVersion = 2
    focus = [ordered]@{
      sessionMinutes = Get-ClampedInt $FocusMinutesInput 45 1 10080
      leaveSeconds = Get-ClampedInt $LeaveInput 300 1 86400
      idleSeconds = Get-ClampedInt $IdleInput 600 1 86400
    }
    trigger = [ordered]@{
      outputMode = @("untilWhitelist", "fixedDuration")[[Math]::Max(0, [Math]::Min(1, $OutputModeCombo.SelectedIndex))]
      overlapMode = @("restart", "extend")[[Math]::Max(0, [Math]::Min(1, $OverlapModeCombo.SelectedIndex))]
      channel = @("both", "A", "B")[[Math]::Max(0, [Math]::Min(2, $ChannelModeCombo.SelectedIndex))]
      strengthA = @($rangeA[0], $rangeA[1])
      strengthB = @($rangeB[0], $rangeB[1])
      waveform = @("constant", "pulse", "ramp", "heartbeat")[[Math]::Max(0, [Math]::Min(3, $WaveformCombo.SelectedIndex))]
      wavePeriodMs = Get-ClampedInt $WavePeriodInput 30 10 1000
      waveIntensity = Get-ClampedInt $WaveIntensityInput 35 0 100
      durationSeconds = Get-ClampedInt $DurationInput 5 1 30
      maxContinuousSeconds = Get-ClampedInt $MaxContinuousInput 10 1 30
      cooldownSeconds = Get-ClampedInt $HoldCooldownInput 60 5 3600
    }
    device = [ordered]@{
      mode = @("http", "ble", "socket")[[Math]::Max(0, [Math]::Min(2, $DeviceModeCombo.SelectedIndex))]
      httpEndpoint = $HttpEndpointInput.Text.Trim()
      bleAddress = $BleAddressInput.Text.Trim()
      socket = [ordered]@{
        mode = @("local", "remote")[[Math]::Max(0, [Math]::Min(1, $SocketServerModeCombo.SelectedIndex))]
        localHost = $LocalSocketHostInput.Text.Trim()
        localPort = Get-ClampedInt $LocalSocketPortInput 5678 1 65535
        remoteServer = $SocketServerInput.Text.Trim()
      }
    }
    safety = [ordered]@{
      httpLimitA = Get-ClampedInt $HttpLimitAInput 80 0 200
      httpLimitB = Get-ClampedInt $HttpLimitBInput 80 0 200
      softLimitA = Get-ClampedInt $SoftLimitAInput 80 0 200
      softLimitB = Get-ClampedInt $SoftLimitBInput 80 0 200
      frequencyBalanceA = Get-ClampedInt $FrequencyBalanceAInput 0 0 255
      frequencyBalanceB = Get-ClampedInt $FrequencyBalanceBInput 0 0 255
      strengthBalanceA = Get-ClampedInt $StrengthBalanceAInput 0 0 255
      strengthBalanceB = Get-ClampedInt $StrengthBalanceBInput 0 0 255
    }
    scope = [ordered]@{
      whitelist = @($WhitelistList.Items | ForEach-Object { [string]$_ })
      blacklist = @($BlacklistList.Items | ForEach-Object { [string]$_ })
    }
  }
}

function Get-SafeDesktopConfiguration {
  return [pscustomobject]@{
    schemaVersion = 2
    focus = [pscustomobject]@{ sessionMinutes = 45; leaveSeconds = 300; idleSeconds = 600 }
    trigger = [pscustomobject]@{
      outputMode = "fixedDuration"; overlapMode = "restart"; channel = "both"
      strengthA = @(10, 20); strengthB = @(10, 20); waveform = "constant"
      wavePeriodMs = 30; waveIntensity = 20; durationSeconds = 1
      maxContinuousSeconds = 10; cooldownSeconds = 60
    }
    device = [pscustomobject]@{
      mode = "http"; httpEndpoint = "http://127.0.0.1:8080"; bleAddress = ""
      socket = [pscustomobject]@{ mode = "local"; localHost = (Get-PreferredLocalIpv4Address); localPort = 5678; remoteServer = "ws://192.168.1.100:5678" }
    }
    safety = [pscustomobject]@{
      httpLimitA = 30; httpLimitB = 30; softLimitA = 30; softLimitB = 30; frequencyBalanceA = 0; frequencyBalanceB = 0
      strengthBalanceA = 0; strengthBalanceB = 0
    }
    scope = [pscustomobject]@{ whitelist = @(); blacklist = @() }
  }
}

function Stop-ForConfigurationChange {
  if ($script:State.OutputActive -or $script:Ble.OutputActive) {
    Invoke-DeviceStop | Out-Null
  }
  if ($null -ne $script:State.SocketClient -or $null -ne $script:State.LocalSocketServer) {
    Reset-SocketConnection
  }
  $script:State.Connected = $false
}

function Set-DesktopConfiguration($Config, [string]$SourceName) {
  $version = ConvertTo-ConfigInt (Get-RequiredConfigValue $Config "schemaVersion") "schemaVersion" 1 2
  $focus = Get-RequiredConfigValue $Config "focus"
  $trigger = Get-RequiredConfigValue $Config "trigger"
  $device = Get-RequiredConfigValue $Config "device"
  $socket = Get-RequiredConfigValue $device "socket"
  $safety = Get-RequiredConfigValue $Config "safety"
  $scope = Get-RequiredConfigValue $Config "scope"

  $sessionMinutes = ConvertTo-ConfigInt (Get-RequiredConfigValue $focus "sessionMinutes") "focus.sessionMinutes" 1 10080
  $leaveSeconds = ConvertTo-ConfigInt (Get-RequiredConfigValue $focus "leaveSeconds") "focus.leaveSeconds" 1 86400
  $idleSeconds = ConvertTo-ConfigInt (Get-RequiredConfigValue $focus "idleSeconds") "focus.idleSeconds" 1 86400
  $outputMode = ConvertTo-ConfigChoice (Get-RequiredConfigValue $trigger "outputMode") "trigger.outputMode" @("untilWhitelist", "fixedDuration")
  $overlapMode = ConvertTo-ConfigChoice (Get-RequiredConfigValue $trigger "overlapMode") "trigger.overlapMode" @("restart", "extend")
  $channel = ConvertTo-ConfigChoice (Get-RequiredConfigValue $trigger "channel") "trigger.channel" @("both", "A", "B")
  $waveform = ConvertTo-ConfigChoice (Get-RequiredConfigValue $trigger "waveform") "trigger.waveform" @("constant", "pulse", "ramp", "heartbeat")
  $strengthA = @(Get-RequiredConfigValue $trigger "strengthA")
  $strengthB = @(Get-RequiredConfigValue $trigger "strengthB")
  if ($strengthA.Count -ne 2 -or $strengthB.Count -ne 2) { throw "强度范围必须包含最小值和最大值。" }
  $strengthAMin = ConvertTo-ConfigInt $strengthA[0] "trigger.strengthA[0]" 0 200
  $strengthAMax = ConvertTo-ConfigInt $strengthA[1] "trigger.strengthA[1]" $strengthAMin 200
  $strengthBMin = ConvertTo-ConfigInt $strengthB[0] "trigger.strengthB[0]" 0 200
  $strengthBMax = ConvertTo-ConfigInt $strengthB[1] "trigger.strengthB[1]" $strengthBMin 200
  $wavePeriod = ConvertTo-ConfigInt (Get-RequiredConfigValue $trigger "wavePeriodMs") "trigger.wavePeriodMs" 10 1000
  $waveIntensity = ConvertTo-ConfigInt (Get-RequiredConfigValue $trigger "waveIntensity") "trigger.waveIntensity" 0 100
  if ($version -eq 1 -and $trigger.PSObject.Properties.Name -notcontains "durationSeconds") {
    $legacyDurationMs = ConvertTo-ConfigInt (Get-RequiredConfigValue $trigger "durationMs") "trigger.durationMs" 100 30000
    $durationSeconds = [Math]::Max(1, [Math]::Min(30, [int][Math]::Ceiling($legacyDurationMs / 1000.0)))
  } else {
    $durationSeconds = ConvertTo-ConfigInt (Get-RequiredConfigValue $trigger "durationSeconds") "trigger.durationSeconds" 1 30
  }
  $maxContinuousSeconds = if ($trigger.PSObject.Properties.Name -contains "maxContinuousSeconds") {
    ConvertTo-ConfigInt $trigger.maxContinuousSeconds "trigger.maxContinuousSeconds" 1 30
  } else { 10 }
  $cooldownSeconds = if ($trigger.PSObject.Properties.Name -contains "cooldownSeconds") {
    ConvertTo-ConfigInt $trigger.cooldownSeconds "trigger.cooldownSeconds" 5 3600
  } else { 60 }
  $deviceMode = ConvertTo-ConfigChoice (Get-RequiredConfigValue $device "mode") "device.mode" @("http", "ble", "socket")
  $httpEndpoint = ConvertTo-ConfigText (Get-RequiredConfigValue $device "httpEndpoint") "device.httpEndpoint" 2048
  $bleAddress = ConvertTo-ConfigText (Get-RequiredConfigValue $device "bleAddress") "device.bleAddress" 64 -AllowEmpty
  $socketMode = ConvertTo-ConfigChoice (Get-RequiredConfigValue $socket "mode") "device.socket.mode" @("local", "remote")
  $localHost = ConvertTo-ConfigText (Get-RequiredConfigValue $socket "localHost") "device.socket.localHost" 255
  $localPort = ConvertTo-ConfigInt (Get-RequiredConfigValue $socket "localPort") "device.socket.localPort" 1 65535
  $remoteServer = ConvertTo-ConfigText (Get-RequiredConfigValue $socket "remoteServer") "device.socket.remoteServer" 2048
  [void](Assert-SecureNetworkEndpoint $httpEndpoint "http")
  [void](Assert-SecureNetworkEndpoint $remoteServer "socket")
  [void](Assert-SecureNetworkEndpoint "ws://$localHost`:$localPort" "socket")
  $softLimitA = ConvertTo-ConfigInt (Get-RequiredConfigValue $safety "softLimitA") "safety.softLimitA" 0 200
  $softLimitB = ConvertTo-ConfigInt (Get-RequiredConfigValue $safety "softLimitB") "safety.softLimitB" 0 200
  $httpLimitA = if ($safety.PSObject.Properties.Name -contains "httpLimitA") { ConvertTo-ConfigInt $safety.httpLimitA "safety.httpLimitA" 0 200 } else { $softLimitA }
  $httpLimitB = if ($safety.PSObject.Properties.Name -contains "httpLimitB") { ConvertTo-ConfigInt $safety.httpLimitB "safety.httpLimitB" 0 200 } else { $softLimitB }
  $frequencyBalanceA = ConvertTo-ConfigInt (Get-RequiredConfigValue $safety "frequencyBalanceA") "safety.frequencyBalanceA" 0 255
  $frequencyBalanceB = ConvertTo-ConfigInt (Get-RequiredConfigValue $safety "frequencyBalanceB") "safety.frequencyBalanceB" 0 255
  $strengthBalanceA = ConvertTo-ConfigInt (Get-RequiredConfigValue $safety "strengthBalanceA") "safety.strengthBalanceA" 0 255
  $strengthBalanceB = ConvertTo-ConfigInt (Get-RequiredConfigValue $safety "strengthBalanceB") "safety.strengthBalanceB" 0 255
  $whitelist = @(Get-RequiredConfigValue $scope "whitelist")
  $blacklist = @(Get-RequiredConfigValue $scope "blacklist")
  if ($whitelist.Count -gt 500 -or $blacklist.Count -gt 500) { throw "黑白名单分别最多允许 500 项。" }
  $validatedWhitelist = @($whitelist | ForEach-Object { ConvertTo-ConfigText $_ "scope.whitelist" 512 })
  $validatedBlacklist = @($blacklist | ForEach-Object { ConvertTo-ConfigText $_ "scope.blacklist" 512 })

  Stop-ForConfigurationChange
  $FocusMinutesInput.Text = [string]$sessionMinutes
  $LeaveInput.Text = [string]$leaveSeconds
  $IdleInput.Text = [string]$idleSeconds
  $OutputModeCombo.SelectedIndex = @("untilWhitelist", "fixedDuration").IndexOf($outputMode)
  $OverlapModeCombo.SelectedIndex = @("restart", "extend").IndexOf($overlapMode)
  $ChannelModeCombo.SelectedIndex = @("both", "A", "B").IndexOf($channel)
  $StrengthARangeInput.Text = "$strengthAMin-$strengthAMax"
  $StrengthBRangeInput.Text = "$strengthBMin-$strengthBMax"
  $WaveformCombo.SelectedIndex = @("constant", "pulse", "ramp", "heartbeat").IndexOf($waveform)
  $WavePeriodInput.Text = [string]$wavePeriod
  $WaveIntensityInput.Text = [string]$waveIntensity
  $DurationInput.Text = [string]$durationSeconds
  $MaxContinuousInput.Text = [string]$maxContinuousSeconds
  $HoldCooldownInput.Text = [string]$cooldownSeconds
  $HttpEndpointInput.Text = $httpEndpoint
  $BleAddressInput.Text = $bleAddress
  $LocalSocketHostInput.Text = $localHost
  $LocalSocketPortInput.Text = [string]$localPort
  $SocketServerInput.Text = $remoteServer
  $HttpLimitAInput.Text = [string]$httpLimitA
  $HttpLimitBInput.Text = [string]$httpLimitB
  $SoftLimitAInput.Text = [string]$softLimitA
  $SoftLimitBInput.Text = [string]$softLimitB
  $FrequencyBalanceAInput.Text = [string]$frequencyBalanceA
  $FrequencyBalanceBInput.Text = [string]$frequencyBalanceB
  $StrengthBalanceAInput.Text = [string]$strengthBalanceA
  $StrengthBalanceBInput.Text = [string]$strengthBalanceB
  $WhitelistList.Items.Clear()
  foreach ($item in $validatedWhitelist) { [void]$WhitelistList.Items.Add($item) }
  $BlacklistList.Items.Clear()
  foreach ($item in $validatedBlacklist) { [void]$BlacklistList.Items.Add($item) }
  $SocketServerModeCombo.SelectedIndex = @("local", "remote").IndexOf($socketMode)
  $DeviceModeCombo.SelectedIndex = @("http", "ble", "socket").IndexOf($deviceMode)
  Refresh-CurrentWindow | Out-Null
  Add-Log "已应用配置：$SourceName（格式版本 $version）"
  Update-View
}

function Export-DesktopConfiguration {
  $dialog = New-Object Microsoft.Win32.SaveFileDialog
  $dialog.Title = "导出写作督促配置"
  $dialog.Filter = "JSON 配置文件 (*.json)|*.json"
  $dialog.FileName = "OCWritingFocus.config.json"
  $dialog.AddExtension = $true
  if ($dialog.ShowDialog() -ne $true) { return }
  $json = (Get-DesktopConfiguration) | ConvertTo-Json -Depth 8
  [IO.File]::WriteAllText($dialog.FileName, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($true)))
  Add-Log "配置已导出：$($dialog.FileName)"
}

function Import-DesktopConfiguration {
  $dialog = New-Object Microsoft.Win32.OpenFileDialog
  $dialog.Title = "导入写作督促配置"
  $dialog.Filter = "JSON 配置文件 (*.json)|*.json"
  $dialog.CheckFileExists = $true
  if ($dialog.ShowDialog() -ne $true) { return }
  try {
    $file = Get-Item -LiteralPath $dialog.FileName
    if ($file.Length -gt 1048576) { throw "配置文件不能超过 1 MB。" }
    $config = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    Set-DesktopConfiguration $config $file.Name
  } catch {
    Add-Log "配置导入失败：$($_.Exception.Message)"
    [Windows.MessageBox]::Show("配置导入失败：`r`n`r`n$($_.Exception.Message)", "导入配置", "OK", "Error") | Out-Null
  }
}

function Reset-SafeDesktopConfiguration {
  $answer = [Windows.MessageBox]::Show(
    "这会停止当前输出、断开设备、清空黑白名单，并恢复低强度固定时长配置。是否继续？",
    "恢复安全默认值",
    "YesNo",
    "Warning")
  if ($answer -ne [Windows.MessageBoxResult]::Yes) { return }
  Set-DesktopConfiguration (Get-SafeDesktopConfiguration) "安全默认值"
  $script:State.Locked = $true
  Add-Log "安全默认值已恢复；为防止误触发，当前保持急停锁定"
  Update-View
}


function Initialize-QrCoder {
  try {
    [void][QRCoder.QRCodeGenerator]
    return
  } catch {
    $candidates = @(
      (Join-Path $script:DesktopSourceRoot "QRCoder.dll"),
      (Join-Path (Split-Path -Parent (Split-Path -Parent $script:DesktopSourceRoot)) "vendor\QRCoder\QRCoder.dll")
    )
    foreach ($candidate in $candidates) {
      if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        Add-Type -Path $candidate
        return
      }
    }
    [void][Reflection.Assembly]::Load("QRCoder")
  }
}

function Set-SocketQrCode([string]$Content) {
  Initialize-QrCoder
  $generator = New-Object QRCoder.QRCodeGenerator
  $data = $generator.CreateQrCode($Content, [QRCoder.QRCodeGenerator+ECCLevel]::M)
  $png = New-Object QRCoder.PngByteQRCode $data
  $bytes = $png.GetGraphic(6)
  $stream = New-Object IO.MemoryStream (,$bytes)
  $bitmap = New-Object Windows.Media.Imaging.BitmapImage
  $bitmap.BeginInit()
  $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
  $bitmap.StreamSource = $stream
  $bitmap.EndInit()
  $bitmap.Freeze()
  $SocketQrImage.Source = $bitmap
  $SocketQrPlaceholder.Visibility = [Windows.Visibility]::Collapsed
  $stream.Dispose()
  $png.Dispose()
  $data.Dispose()
  $generator.Dispose()
}

function Set-SocketBindingInfo([string]$ServerUri, [string]$ClientId) {
  $server = $ServerUri.TrimEnd("/")
  $manualAddress = "$server/$ClientId"
  $qr = "https://www.dungeon-lab.com/app-download.php#DGLAB-SOCKET#$manualAddress"
  $SocketManualAddressText.Text = $manualAddress
  $SocketQrContentText.Text = $qr
  Set-SocketQrCode $qr
}

function Reset-SocketConnection {
  if ($null -ne $script:State.SocketTransport) {
    try { $script:State.SocketTransport.Dispose() } catch {}
  }
  if ($null -ne $script:State.SocketClient) {
    try { $script:State.SocketClient.Abort() } catch {}
    try { $script:State.SocketClient.Dispose() } catch {}
  }
  if ($null -ne $script:State.LocalSocketServer) {
    try { $script:State.LocalSocketServer.Stop() } catch {}
    try { $script:State.LocalSocketServer.Dispose() } catch {}
  }
  $script:State.SocketClient = $null
  $script:State.SocketTransport = $null
  $script:State.LocalSocketServer = $null
  $script:State.LocalSocketLastError = ""
  $script:State.SocketClientId = ""
  $script:State.SocketTargetId = ""
  $script:State.SocketServerUri = ""
  $script:State.SocketReceiveTask = $null
  $script:State.SocketReceiveBuffer = $null
  $script:State.SocketWatchdogStopCount = 0
  $script:State.SocketAppStrengthA = 0
  $script:State.SocketAppStrengthB = 0
  $script:State.SocketAppLimitA = 0
  $script:State.SocketAppLimitB = 0
  $script:State.SocketHasAppLimits = $false
  $script:State.SocketStrengthUpdateCount = 0
  $script:State.Connected = $false
  Set-ActualStrengthState 0 0 "Socket 未连接" $false
  $SocketQrContentText.Text = ""
  $SocketManualAddressText.Text = ""
  $SocketQrImage.Source = $null
  $SocketQrPlaceholder.Visibility = [Windows.Visibility]::Visible
  $SocketBindStatusText.Text = "未连接服务器"
  $SocketAppLimitsText.Text = "等待 App 上报 A/B 强度上限；未上报前禁止输出"
}

function Set-SocketAppStrengthState([int]$StrengthA, [int]$StrengthB, [int]$LimitA, [int]$LimitB) {
  $a = [Math]::Max(0, [Math]::Min(200, $StrengthA))
  $b = [Math]::Max(0, [Math]::Min(200, $StrengthB))
  $limitAValue = [Math]::Max(0, [Math]::Min(200, $LimitA))
  $limitBValue = [Math]::Max(0, [Math]::Min(200, $LimitB))
  $limitsChanged = -not $script:State.SocketHasAppLimits -or $limitAValue -ne $script:State.SocketAppLimitA -or $limitBValue -ne $script:State.SocketAppLimitB
  $script:State.SocketAppStrengthA = $a
  $script:State.SocketAppStrengthB = $b
  $script:State.SocketAppLimitA = $limitAValue
  $script:State.SocketAppLimitB = $limitBValue
  $script:State.SocketHasAppLimits = $true
  $SocketAppLimitsText.Text = "当前 A=$a / 上限 $limitAValue；B=$b / 上限 $limitBValue（来自 App）"
  Set-ActualStrengthState $a $b "Socket App 实时回报"
  if ($limitsChanged) { Add-Log "已读取 DG-Lab App 安全上限：A=$limitAValue，B=$limitBValue；本软件强度配置保持不变" }
  Update-View

  if ($script:State.OutputActive -and $null -ne $script:State.OutputProfile) {
    $newA = [Math]::Min([int]$script:State.OutputProfile.AStrength, $limitAValue)
    $newB = [Math]::Min([int]$script:State.OutputProfile.BStrength, $limitBValue)
    if ($newA -ne $script:State.OutputProfile.AStrength -or $newB -ne $script:State.OutputProfile.BStrength) {
      $script:State.OutputProfile.AStrength = $newA
      $script:State.OutputProfile.BStrength = $newB
      try {
        Invoke-SocketSend "strength-1+2+$newA"
        Invoke-SocketSend "strength-2+2+$newB"
        Add-Log "App 上限降低，活动输出已立即降至 A=$newA，B=$newB"
      } catch {
        Add-Log "App 上限降低但强度下调发送失败，正在立即停止：$($_.Exception.Message)"
        Invoke-SocketStop | Out-Null
      }
    }
  }
}

function Try-ApplySocketStrengthMessage([string]$Body) {
  if ($Body -match '^strength-(\d{1,3})\+(\d{1,3})\+(\d{1,3})\+(\d{1,3})$') {
    Set-SocketAppStrengthState ([int]$Matches[1]) ([int]$Matches[2]) ([int]$Matches[3]) ([int]$Matches[4])
    return $true
  }
  return $false
}

function Start-SocketReceive {
  if ($null -eq $script:State.SocketClient -or $script:State.SocketClient.State -ne [System.Net.WebSockets.WebSocketState]::Open) { return }
  $buffer = New-Object byte[] 4096
  $segment = New-Object 'System.ArraySegment[byte]' (,$buffer)
  $script:State.SocketReceiveBuffer = $buffer
  $script:State.SocketReceiveTask = $script:State.SocketClient.ReceiveAsync($segment, [Threading.CancellationToken]::None)
}

function Update-SocketReceive {
  $task = $script:State.SocketReceiveTask
  if ($null -eq $task -or -not $task.IsCompleted) { return }
  try {
    $result = $task.Result
    if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
      throw "Socket 服务器已关闭连接"
    }
    $json = [Text.Encoding]::UTF8.GetString($script:State.SocketReceiveBuffer, 0, $result.Count)
    $message = $json | ConvertFrom-Json
    if ($message.type -eq "bind" -and $message.message -eq "targetId") {
      $script:State.SocketClientId = [string]$message.clientId
      if ($null -ne $script:State.SocketTransport) { $script:State.SocketTransport.UpdateBinding($script:State.SocketClientId, "") }
      Set-SocketBindingInfo $script:State.SocketServerUri $script:State.SocketClientId
      $SocketBindStatusText.Text = "服务器已注册，等待 App 扫码或手动连接"
      Add-Log "Socket 终端已注册，等待 App 绑定：$($script:State.SocketClientId)"
    } elseif ($message.type -eq "bind" -and [string]$message.message -eq "200" -and [string]$message.clientId -eq $script:State.SocketClientId) {
      $script:State.SocketTargetId = [string]$message.targetId
      $script:State.SocketHasAppLimits = $false
      $SocketAppLimitsText.Text = "App 已绑定，等待上报 A/B 强度上限；当前禁止输出"
      if ($null -ne $script:State.SocketTransport) { $script:State.SocketTransport.UpdateBinding($script:State.SocketClientId, $script:State.SocketTargetId) }
      $script:State.Connected = $true
      $SocketBindStatusText.Text = "App 已绑定，可以发送控制指令"
      Add-Log "Socket App 已绑定：$($script:State.SocketTargetId)"
    } elseif ($message.type -eq "msg" -and $script:State.Connected -and
      [string]$message.clientId -eq $script:State.SocketClientId -and
      [string]$message.targetId -eq $script:State.SocketTargetId) {
      [void](Try-ApplySocketStrengthMessage ([string]$message.message))
    } elseif ($message.type -eq "break") {
      $script:State.Connected = $false
      $script:State.SocketTargetId = ""
      $script:State.SocketHasAppLimits = $false
      $SocketAppLimitsText.Text = "等待 App 上报 A/B 强度上限；未上报前禁止输出"
      $SocketBindStatusText.Text = "App 已断开，请重新扫码绑定"
      Add-Log "Socket App 已断开"
    }
    Start-SocketReceive
  } catch {
    Add-Log "Socket 接收失败：$($_.Exception.Message)"
    Reset-SocketConnection
  }
}

function Get-PreferredLocalIpv4Address {
  $adapters = [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object {
    $_.OperationalStatus -eq [Net.NetworkInformation.OperationalStatus]::Up -and
    $_.NetworkInterfaceType -ne [Net.NetworkInformation.NetworkInterfaceType]::Loopback
  }
  $adapters = $adapters | Sort-Object @{ Expression = {
    if ($_.NetworkInterfaceType -eq [Net.NetworkInformation.NetworkInterfaceType]::Wireless80211) { 0 }
    elseif ($_.NetworkInterfaceType -eq [Net.NetworkInformation.NetworkInterfaceType]::Ethernet) { 1 }
    else { 2 }
  } }
  foreach ($adapter in $adapters) {
    try {
      $properties = $adapter.GetIPProperties()
      $hasIpv4Gateway = $null -ne ($properties.GatewayAddresses | Where-Object {
        $_.Address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and $_.Address.ToString() -ne "0.0.0.0"
      } | Select-Object -First 1)
      if (-not $hasIpv4Gateway) { continue }
      foreach ($unicast in $properties.UnicastAddresses) {
        $address = $unicast.Address
        if ($address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { continue }
        $probeUri = New-Object Uri "ws://$($address.ToString())"
        if (Test-TrustedPlaintextHost $probeUri) { return $address.ToString() }
      }
    } catch {}
  }
  $addresses = [Net.Dns]::GetHostAddresses([Net.Dns]::GetHostName()) | Where-Object {
    $_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and -not [Net.IPAddress]::IsLoopback($_)
  }
  $preferred = $addresses | Where-Object { $_.ToString() -match '^(192\.168\.|10\.|169\.254\.|172\.(1[6-9]|2[0-9]|3[01])\.)' } | Select-Object -First 1
  if ($null -eq $preferred) { return "127.0.0.1" }
  return $preferred.ToString()
}

function Invoke-LocalSocketStart {
  try {
    Reset-SocketConnection
    $hostText = $LocalSocketHostInput.Text.Trim()
    $port = Get-ClampedInt $LocalSocketPortInput 5678 1 65535
    $advertisedUri = Assert-SecureNetworkEndpoint "ws://$hostText`:$port" "socket"
    $server = New-Object LocalDglabSocketServer
    $server.Start($advertisedUri.DnsSafeHost, $port)
    $script:State.LocalSocketServer = $server
    $script:State.SocketClientId = $server.ClientId
    $script:State.SocketServerUri = $advertisedUri.AbsoluteUri.TrimEnd("/")
    Set-SocketBindingInfo $script:State.SocketServerUri $script:State.SocketClientId
    $SocketBindStatusText.Text = "本地服务器已启动，等待 App 扫码或手动连接"
    Add-Log "本地 Socket 服务器已安全绑定：$($advertisedUri.DnsSafeHost):$port"
  } catch {
    Reset-SocketConnection
    Add-Log "本地 Socket 服务器启动失败：$($_.Exception.Message)"
  }
}

function Update-LocalSocketServer {
  $server = $script:State.LocalSocketServer
  if ($null -eq $server) { return }
  if (-not [string]::IsNullOrWhiteSpace($server.LastError) -and $server.LastError -ne $script:State.LocalSocketLastError) {
    $script:State.LocalSocketLastError = $server.LastError
    Add-Log "本地 Socket 服务器错误：$($server.LastError)"
  }
  if ($server.IsBound -and -not $script:State.Connected) {
    $script:State.SocketTargetId = $server.TargetId
    $script:State.Connected = $true
    $script:State.SocketHasAppLimits = $false
    $SocketAppLimitsText.Text = "App 已绑定，等待上报 A/B 强度上限；当前禁止输出"
    $SocketBindStatusText.Text = "App 已绑定本地服务器，等待强度上限"
    Add-Log "Socket App 已绑定本地服务器：$($script:State.SocketTargetId)"
  } elseif (-not $server.IsBound -and $script:State.Connected) {
    $script:State.Connected = $false
    $script:State.SocketTargetId = ""
    $script:State.SocketHasAppLimits = $false
    $SocketAppLimitsText.Text = "等待 App 上报 A/B 强度上限；未上报前禁止输出"
    $SocketBindStatusText.Text = "App 已断开，请重新扫码绑定"
    Add-Log "Socket App 已从本地服务器断开"
  }
  if ($server.HasAppLimits -and $server.StrengthUpdateCount -ne $script:State.SocketStrengthUpdateCount) {
    $script:State.SocketStrengthUpdateCount = $server.StrengthUpdateCount
    Set-SocketAppStrengthState $server.AppStrengthA $server.AppStrengthB $server.AppLimitA $server.AppLimitB
  }
}

function Invoke-RemoteSocketConnect {
  try {
    Reset-SocketConnection
    $uri = Assert-SecureNetworkEndpoint $SocketServerInput.Text "socket"
    $text = $uri.AbsoluteUri.TrimEnd("/")
    $client = New-Object System.Net.WebSockets.ClientWebSocket
    $connectTimeout = New-Object Threading.CancellationTokenSource 5000
    try {
      $client.ConnectAsync($uri, $connectTimeout.Token).Wait()
    } finally {
      $connectTimeout.Dispose()
    }
    if ($client.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
      throw "Socket 连接未进入 Open 状态。"
    }
    $script:State.SocketClient = $client
    $script:State.SocketTransport = New-Object DglabRemoteSocketTransport $client
    $script:State.SocketServerUri = $text
    $SocketBindStatusText.Text = "服务器已连接，正在注册终端…"
    Start-SocketReceive
    Add-Log "Socket 服务器已连接，等待注册消息：$text"
  } catch {
    Reset-SocketConnection
    Add-Log "Socket 连接失败：$($_.Exception.Message)"
  }
}

function Invoke-SocketConnect {
  if ($script:State.SocketServerMode -eq "local") {
    Invoke-LocalSocketStart
  } else {
    Invoke-RemoteSocketConnect
  }
}

function Invoke-SocketSend([string]$Command) {
  if (-not $script:State.Connected -or [string]::IsNullOrWhiteSpace($script:State.SocketClientId) -or [string]::IsNullOrWhiteSpace($script:State.SocketTargetId)) {
    throw "Socket App 尚未完成绑定"
  }
  if ($null -ne $script:State.LocalSocketServer) {
    $script:State.LocalSocketServer.SendCommand($Command)
    return
  }
  if ($null -eq $script:State.SocketTransport) { throw "Socket 安全传输器未初始化" }
  $script:State.SocketTransport.SendCommand($Command)
}

function Invoke-SocketStop {
  $transport = if ($null -ne $script:State.LocalSocketServer) { $script:State.LocalSocketServer } else { $script:State.SocketTransport }
  if ($null -eq $transport) {
    Add-Log "Socket 停止失败：安全传输器不可用"
    return $false
  }
  try {
    $stopped = $transport.StopOutputReliable(3)
    if ($stopped) {
      $transport.CancelSafetyTimeout()
      Set-ActualStrengthState 0 0 "Socket 停止命令已下发"
      Add-Log "Socket A/B 已归零并清除波形（独立命令、最多重试 3 次）"
      return $true
    }
    Add-Log "Socket 停止未全部成功：$($transport.LastError)；后台看门狗仍保持待命"
    return $false
  } catch {
    Add-Log "Socket 停止异常：$($_.Exception.Message)；后台看门狗仍保持待命"
    return $false
  }
}

function Arm-SocketSafetyWatchdog([int]$TimeoutMs) {
  $transport = if ($null -ne $script:State.LocalSocketServer) { $script:State.LocalSocketServer } else { $script:State.SocketTransport }
  if ($null -eq $transport) { throw "Socket 安全看门狗不可用" }
  $transport.ArmSafetyTimeout($TimeoutMs)
  $script:State.SocketWatchdogStopCount = $transport.WatchdogStopCount
}

function Update-SocketSafetyWatchdogStatus {
  $transport = if ($null -ne $script:State.LocalSocketServer) { $script:State.LocalSocketServer } else { $script:State.SocketTransport }
  if ($null -eq $transport) { return }
  if ($transport.WatchdogStopCount -gt $script:State.SocketWatchdogStopCount) {
    $script:State.SocketWatchdogStopCount = $transport.WatchdogStopCount
    if ($transport.LastWatchdogStopSucceeded) {
      Set-ActualStrengthState 0 0 "Socket 看门狗已下发"
      Add-Log "Socket 后台安全看门狗已独立执行 A/B 归零"
    } else {
      Add-Log "警告：Socket 后台安全看门狗未能完成全部停止命令：$($transport.LastError)"
    }
  }
}

function Invoke-SocketActivate($Profile) {
  try {
    $Profile = Limit-TriggerProfile $Profile
    $a = if ($Profile.Channel -in @("A", "both")) { $Profile.AStrength } else { 0 }
    $b = if ($Profile.Channel -in @("B", "both")) { $Profile.BStrength } else { 0 }
    Invoke-SocketSend "clear-1"
    Invoke-SocketSend "clear-2"
    Invoke-SocketSend "strength-1+2+$a"
    Invoke-SocketSend "strength-2+2+$b"
    Set-ActualStrengthState $a $b "Socket 已下发，等待 App 回报"
    return $true
  } catch {
    Add-Log "Socket 触发失败：$($_.Exception.Message)"
    return $false
  }
}


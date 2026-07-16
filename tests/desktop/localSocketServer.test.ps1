$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtimeTypesScript = Join-Path $projectRoot "src\desktop\parts\00-runtime-types.ps1"
$source = Get-Content -Raw $runtimeTypesScript
$match = [regex]::Match(
  $source,
  '-TypeDefinition @"\r?\n(?<code>.*?)\r?\n"@',
  [Text.RegularExpressions.RegexOptions]::Singleline
)
if (-not $match.Success) { throw "未找到桌面脚本中的本地 Socket 服务端源码。" }

Add-Type -ReferencedAssemblies @("System.dll", "System.Core.dll", "System.Web.Extensions.dll") -TypeDefinition $match.Groups["code"].Value

function Receive-WebSocketText($WebSocket) {
  $buffer = New-Object byte[] 4096
  $segment = New-Object 'System.ArraySegment[byte]' (,$buffer)
  $result = $WebSocket.ReceiveAsync($segment, [Threading.CancellationToken]::None).Result
  return [Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
}

$probe = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback, 0)
$probe.Start()
$port = ([Net.IPEndPoint]$probe.LocalEndpoint).Port
$probe.Stop()

$server = New-Object LocalDglabSocketServer
$client = New-Object Net.WebSockets.ClientWebSocket
try {
  $server.Start($port)
  $wrongClient = New-Object Net.WebSockets.ClientWebSocket
  try {
    $wrongPathRejected = $false
    try { $wrongClient.ConnectAsync((New-Object Uri "ws://127.0.0.1:$port/wrong-client-id"), [Threading.CancellationToken]::None).Wait() }
    catch { $wrongPathRejected = $true }
    if (-not $wrongPathRejected) { throw "本地 Socket 服务端接受了错误的二维码客户端 ID。" }
  } finally {
    try { $wrongClient.Abort() } catch {}
    try { $wrongClient.Dispose() } catch {}
  }

  # DG-Lab App may connect to the server root even when the QR payload contains
  # /<clientId>. Pairing remains authenticated by the clientId in the bind frame.
  $uri = New-Object Uri "ws://127.0.0.1:$port/"
  $client.ConnectAsync($uri, [Threading.CancellationToken]::None).Wait()

  $registration = (Receive-WebSocketText $client) | ConvertFrom-Json
  if ($registration.type -ne "bind" -or $registration.message -ne "targetId") {
    throw "服务端没有发送标准注册消息。"
  }

  # The official Socket server does not drop an App merely because its bind
  # frame takes more than five seconds to arrive.
  Start-Sleep -Milliseconds 5200
  if ($client.State -ne [Net.WebSockets.WebSocketState]::Open -or -not [string]::IsNullOrWhiteSpace($server.LastError)) {
    throw "本地 Socket 服务端在等待 App 绑定时错误触发了读取超时：$($server.LastError)"
  }

  $bind = @{
    type = "bind"
    clientId = $server.ClientId
    targetId = $registration.clientId
    message = "DGLAB"
  } | ConvertTo-Json -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($bind)
  $segment = New-Object 'System.ArraySegment[byte]' (,$bytes)
  $client.SendAsync($segment, [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()

  $bindReply = (Receive-WebSocketText $client) | ConvertFrom-Json
  if ([string]$bindReply.message -ne "200" -or -not $server.IsBound) {
    throw "本地 Socket 服务端绑定失败。"
  }

  $strengthReport = @{
    type = "msg"
    clientId = $server.ClientId
    targetId = $registration.clientId
    message = "strength-12+24+30+40"
  } | ConvertTo-Json -Compress
  $reportBytes = [Text.Encoding]::UTF8.GetBytes($strengthReport)
  $reportSegment = New-Object 'System.ArraySegment[byte]' (,$reportBytes)
  $client.SendAsync($reportSegment, [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()
  $deadline = [DateTime]::UtcNow.AddSeconds(2)
  while (-not $server.HasAppLimits -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 20 }
  if (-not $server.HasAppLimits -or $server.AppStrengthA -ne 12 -or $server.AppStrengthB -ne 24 -or $server.AppLimitA -ne 30 -or $server.AppLimitB -ne 40) {
    throw "本地 Socket 服务端没有读取 App 上报的当前强度和上限。"
  }

  $acceptedUpdateCount = $server.StrengthUpdateCount
  $spoofedReport = @{
    type = "msg"
    clientId = "spoofed-client"
    targetId = $server.ClientId
    message = "strength-199+199+200+200"
  } | ConvertTo-Json -Compress
  $spoofedBytes = [Text.Encoding]::UTF8.GetBytes($spoofedReport)
  $spoofedSegment = New-Object 'System.ArraySegment[byte]' (,$spoofedBytes)
  $client.SendAsync($spoofedSegment, [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()
  Start-Sleep -Milliseconds 100
  if ($server.StrengthUpdateCount -ne $acceptedUpdateCount) {
    throw "本地 Socket 服务端接受了 ID 不匹配的伪造强度上报。"
  }

  $server.SendCommand("strength-1+2+12")
  $command = (Receive-WebSocketText $client) | ConvertFrom-Json
  if ($command.type -ne "msg" -or $command.message -ne "strength-1+2+12") {
    throw "本地 Socket 服务端控制指令转发失败。"
  }

  if (-not $server.StopOutputReliable(3)) {
    throw "本地 Socket 可靠停止返回失败。"
  }
  $expectedStop = @("strength-1+2+0", "strength-2+2+0", "clear-1", "clear-2")
  foreach ($expected in $expectedStop) {
    $stopMessage = (Receive-WebSocketText $client) | ConvertFrom-Json
    if ($stopMessage.message -ne $expected) {
      throw "可靠停止顺序错误：期望 $expected，实际 $($stopMessage.message)。"
    }
  }

  $server.ArmSafetyTimeout(200)
  foreach ($expected in $expectedStop) {
    $watchdogMessage = (Receive-WebSocketText $client) | ConvertFrom-Json
    if ($watchdogMessage.message -ne $expected) {
      throw "本地后台看门狗停止顺序错误：期望 $expected，实际 $($watchdogMessage.message)。"
    }
  }
  if ($server.WatchdogStopCount -lt 1 -or -not $server.LastWatchdogStopSucceeded) {
    throw "本地后台安全看门狗未记录成功停止。"
  }

  $remoteTransport = New-Object DglabRemoteSocketTransport $client
  try {
    $remoteTransport.UpdateBinding("desktop-test", "app-test")
    $remoteTransport.ArmSafetyTimeout(200)
    $deadline = [DateTime]::UtcNow.AddSeconds(3)
    while ($remoteTransport.WatchdogStopCount -lt 1 -and [DateTime]::UtcNow -lt $deadline) {
      Start-Sleep -Milliseconds 25
    }
    if ($remoteTransport.WatchdogStopCount -lt 1 -or -not $remoteTransport.LastWatchdogStopSucceeded) {
      throw "外部 Socket 后台安全看门狗未独立完成停止发送。"
    }
  } finally {
    $remoteTransport.Dispose()
  }

  Write-Output "Local Socket App limits, reliable stop, and independent watchdog: OK"
} finally {
  try { $client.Abort() } catch {}
  try { $client.Dispose() } catch {}
  try { $server.Dispose() } catch {}
}

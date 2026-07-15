$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$desktopScript = Join-Path $projectRoot "src\desktop\OCWritingFocusApp.Wpf.ps1"
$source = Get-Content -Raw $desktopScript
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
  $uri = New-Object Uri "ws://127.0.0.1:$port/$($server.ClientId)"
  $client.ConnectAsync($uri, [Threading.CancellationToken]::None).Wait()

  $registration = (Receive-WebSocketText $client) | ConvertFrom-Json
  if ($registration.type -ne "bind" -or $registration.message -ne "targetId") {
    throw "服务端没有发送标准注册消息。"
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

  $server.SendCommand("strength-1+2+12")
  $command = (Receive-WebSocketText $client) | ConvertFrom-Json
  if ($command.type -ne "msg" -or $command.message -ne "strength-1+2+12") {
    throw "本地 Socket 服务端控制指令转发失败。"
  }

  Write-Output "Local Socket server protocol: OK"
} finally {
  try { $client.Abort() } catch {}
  try { $client.Dispose() } catch {}
  try { $server.Dispose() } catch {}
}

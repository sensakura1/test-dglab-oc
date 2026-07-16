using System.Net;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace OCWritingFocus.Core;

public sealed partial class SocketDeviceAdapter(SocketConfig config) : IDeviceAdapter
{
    private readonly SemaphoreSlim _sendLock = new(1, 1);
    private ClientWebSocket? _client;
    private WebSocket? _socket;
    private HttpListener? _listener;
    private CancellationTokenSource? _lifetime;
    private string _clientId = RandomId();
    private string _targetId = "";
    public string QrText { get; private set; } = "";
    public DeviceStatus Status { get; private set; } = new(false, "等待 App 绑定", "Socket 未连接");

    public async Task ConnectAsync(CancellationToken cancellationToken)
    {
        _lifetime = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        if (config.Mode == "local") await StartLocalAsync(_lifetime.Token);
        else await ConnectRemoteAsync(_lifetime.Token);
    }

    private Task StartLocalAsync(CancellationToken cancellationToken)
    {
        ValidateSocketHost(config.LocalHost, false);
        var prefixHost = config.LocalHost is "0.0.0.0" or "::" ? "+" : config.LocalHost;
        _listener = new HttpListener();
        _listener.Prefixes.Add($"http://{prefixHost}:{config.LocalPort}/");
        _listener.Start();
        QrText = $"ws://{config.LocalHost}:{config.LocalPort}/{_clientId}";
        Status = Status with { Text = "本地服务器已启动，等待 App 绑定", Source = "Socket 本地服务器" };
        _ = AcceptLoopAsync(cancellationToken);
        return Task.CompletedTask;
    }

    private async Task AcceptLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested && _listener?.IsListening == true)
        {
            try
            {
                var context = await _listener.GetContextAsync().WaitAsync(cancellationToken);
                var path = context.Request.Url?.AbsolutePath.Trim('/') ?? "";
                if (!context.Request.IsWebSocketRequest || path.Length > 0 && !path.Equals(_clientId, StringComparison.OrdinalIgnoreCase))
                { context.Response.StatusCode = 404; context.Response.Close(); continue; }
                var upgraded = await context.AcceptWebSocketAsync(null);
                _socket?.Dispose(); _socket = upgraded.WebSocket;
                _targetId = RandomId();
                Status = Status with { Connected = true, Text = "App 已绑定，等待强度上限", Source = "Socket App" };
                _ = ReadLoopAsync(_socket, cancellationToken);
            }
            catch (OperationCanceledException) { return; }
            catch (Exception ex) { Status = Status with { Connected = false, Text = $"本地 Socket 错误：{ex.Message}" }; }
        }
    }

    private async Task ConnectRemoteAsync(CancellationToken cancellationToken)
    {
        var uri = ValidateSocketUri(config.RemoteServer);
        _client = new ClientWebSocket();
        await _client.ConnectAsync(uri, cancellationToken);
        _socket = _client;
        QrText = uri.ToString().TrimEnd('/') + "/" + _clientId;
        Status = Status with { Text = "服务器已连接，等待注册与 App 绑定", Source = "Socket 外部服务器" };
        _ = ReadLoopAsync(_socket, cancellationToken);
    }

    private async Task ReadLoopAsync(WebSocket socket, CancellationToken cancellationToken)
    {
        var buffer = new byte[8192];
        try
        {
            while (socket.State == WebSocketState.Open && !cancellationToken.IsCancellationRequested)
            {
                using var stream = new MemoryStream();
                WebSocketReceiveResult result;
                do { result = await socket.ReceiveAsync(buffer, cancellationToken); stream.Write(buffer, 0, result.Count); } while (!result.EndOfMessage);
                if (result.MessageType == WebSocketMessageType.Close) break;
                ApplyMessage(Encoding.UTF8.GetString(stream.ToArray()));
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { Status = Status with { Text = $"App 连接中断：{ex.Message}" }; }
        finally { Status = Status with { Connected = false, HasLimits = false }; }
    }

    private void ApplyMessage(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        var type = Value(root, "type"); var message = Value(root, "message");
        if (type == "bind" && message == "targetId") { _clientId = Value(root, "clientId"); Status = Status with { Text = "服务器已注册，等待 App 绑定" }; }
        else if (type == "bind" && message == "200") { _targetId = Value(root, "targetId"); Status = Status with { Connected = true, Text = "App 已绑定，等待强度上限" }; }
        else if (type == "break") { _targetId = ""; Status = Status with { Connected = false, HasLimits = false, Text = "App 已断开，请重新绑定" }; }
        else if (type == "msg") ApplyStrength(message);
    }

    private void ApplyStrength(string message)
    {
        var match = StrengthRegex().Match(message);
        if (!match.Success) return;
        var values = match.Groups.Cast<Group>().Skip(1).Select(x => Math.Clamp(int.Parse(x.Value), 0, 200)).ToArray();
        Status = Status with { Connected = true, ActualA = values[0], ActualB = values[1], LimitA = values[2], LimitB = values[3], Known = true, HasLimits = true,
            Source = "Socket App 实时回报", Text = $"当前 A={values[0]} / 上限 {values[2]}；B={values[1]} / 上限 {values[3]}" };
    }

    public async Task ActivateAsync(OutputProfile profile, CancellationToken cancellationToken)
    {
        if (!Status.HasLimits) throw new InvalidOperationException("尚未获得 App A/B 安全上限，禁止输出。 ");
        var a = Math.Min(profile.StrengthA, Status.LimitA); var b = Math.Min(profile.StrengthB, Status.LimitB);
        foreach (var command in new[] { "clear-1", "clear-2", $"strength-1+2+{a}", $"strength-2+2+{b}" }) await SendAsync(command, cancellationToken);
        Status = Status with { ActualA = a, ActualB = b, Known = true, Source = "Socket 已下发，等待 App 回报" };
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        if (_socket?.State == WebSocketState.Open && _targetId.Length > 0)
            foreach (var command in new[] { "strength-1+2+0", "strength-2+2+0", "clear-1", "clear-2" }) await SendAsync(command, cancellationToken);
        Status = Status with { ActualA = 0, ActualB = 0, Known = true, Source = "Socket 停止命令已下发" };
    }

    private async Task SendAsync(string message, CancellationToken cancellationToken)
    {
        if (_socket?.State != WebSocketState.Open || _targetId.Length == 0) throw new InvalidOperationException("Socket App 尚未完成绑定。 ");
        var bytes = JsonSerializer.SerializeToUtf8Bytes(new { type = "msg", clientId = _clientId, targetId = _targetId, message });
        await _sendLock.WaitAsync(cancellationToken);
        try { await _socket.SendAsync(bytes, WebSocketMessageType.Text, true, cancellationToken); }
        finally { _sendLock.Release(); }
    }

    public async Task DisconnectAsync(CancellationToken cancellationToken)
    {
        try { await StopAsync(cancellationToken); } catch { }
        _lifetime?.Cancel(); _listener?.Stop(); _listener?.Close();
        if (_socket?.State == WebSocketState.Open) await _socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "disconnect", cancellationToken);
        _socket?.Dispose(); _client?.Dispose();
        Status = new(false, "等待 App 绑定", "Socket 已断开");
    }

    public async ValueTask DisposeAsync() => await DisconnectAsync(CancellationToken.None);

    private static string Value(JsonElement root, string name) => root.TryGetProperty(name, out var item) ? item.GetString() ?? "" : "";
    private static string RandomId() => Convert.ToHexString(RandomNumberGenerator.GetBytes(16)).ToLowerInvariant();
    private static Uri ValidateSocketUri(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme is not ("ws" or "wss")) throw new InvalidOperationException("Socket 地址必须使用 WS/WSS。 ");
        if (uri.Scheme == "ws") ValidateSocketHost(uri.Host, true);
        return uri;
    }
    private static void ValidateSocketHost(string host, bool remote)
    {
        if (host.Equals("localhost", StringComparison.OrdinalIgnoreCase)) return;
        if (!IPAddress.TryParse(host, out var ip)) { if (remote) throw new InvalidOperationException("远程域名必须使用 WSS。 "); return; }
        var b = ip.GetAddressBytes();
        if (IPAddress.IsLoopback(ip) || b.Length == 4 && (b[0] == 10 || b[0] == 127 || b[0] == 192 && b[1] == 168 || b[0] == 172 && b[1] is >= 16 and <= 31 || b[0] == 169 && b[1] == 254)) return;
        throw new InvalidOperationException("WS 仅允许回环或私有/链路本地地址；公网请使用 WSS。 ");
    }

    [GeneratedRegex("^strength-(\\d{1,3})\\+(\\d{1,3})\\+(\\d{1,3})\\+(\\d{1,3})$")]
    private static partial Regex StrengthRegex();
}

using System.Net;
using System.Net.Http.Json;

namespace OCWritingFocus.Core;

public sealed class HttpDeviceAdapter(string endpoint, int limitA, int limitB, HttpClient? client = null) : IDeviceAdapter
{
    private readonly HttpClient _client = client ?? new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
    public DeviceStatus Status { get; private set; } = new(false, "真实桥接未连接", "未连接", LimitA: limitA, LimitB: limitB, HasLimits: true);

    public async Task ConnectAsync(CancellationToken cancellationToken)
    {
        var response = await _client.GetAsync(ActionUri("status"), cancellationToken);
        response.EnsureSuccessStatusCode();
        Status = Status with { Connected = true, Text = "真实桥接已连接", Source = "HTTP 桥接" };
    }

    public async Task ActivateAsync(OutputProfile profile, CancellationToken cancellationToken)
    {
        RequireConnected();
        var a = Math.Min(profile.StrengthA, limitA); var b = Math.Min(profile.StrengthB, limitB);
        var duration = profile.HoldUntilWhitelist ? profile.MaxContinuous : profile.Duration;
        var body = new { action = "activate", intensity = Math.Max(a, b), intensityA = a, intensityB = b,
            durationMs = (long)duration.TotalMilliseconds, channel = profile.Channel, pattern = profile.Waveform,
            pulseId = profile.Waveform, overrides = profile.RestartOnRepeat, wavePeriodMs = profile.WavePeriodMs,
            waveIntensity = profile.WaveIntensity, softLimitA = limitA, softLimitB = limitB };
        var response = await _client.PostAsJsonAsync(ActionUri("activate"), body, cancellationToken);
        response.EnsureSuccessStatusCode();
        Status = Status with { ActualA = a, ActualB = b, Known = true, Source = "HTTP 桥接已确认接收" };
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        if (!Status.Connected) return;
        var response = await _client.PostAsJsonAsync(ActionUri("stop"), new { action = "stop" }, cancellationToken);
        response.EnsureSuccessStatusCode();
        Status = Status with { ActualA = 0, ActualB = 0, Known = true, Source = "HTTP 桥接已确认接收" };
    }

    public async Task DisconnectAsync(CancellationToken cancellationToken)
    {
        if (Status.Connected) await StopAsync(cancellationToken);
        Status = Status with { Connected = false, Known = false, Text = "真实桥接未连接", Source = "设备已断开" };
    }

    public async ValueTask DisposeAsync() { await DisconnectAsync(CancellationToken.None); _client.Dispose(); }

    private Uri ActionUri(string action)
    {
        if (!Uri.TryCreate(endpoint.Trim(), UriKind.Absolute, out var uri)) throw new InvalidOperationException("HTTP 桥接地址无效。 ");
        if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps) throw new InvalidOperationException("HTTP 桥接仅支持 HTTP/HTTPS。 ");
        if (uri.Scheme == Uri.UriSchemeHttp && !IsPrivateOrLoopback(uri.Host)) throw new InvalidOperationException("远程地址必须使用 HTTPS；HTTP 仅允许本机或私有网络。 ");
        var builder = new UriBuilder(uri);
        var path = builder.Path.TrimEnd('/');
        foreach (var suffix in new[] { "/activate", "/stop", "/status" }) if (path.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)) path = path[..^suffix.Length];
        builder.Path = $"{path}/{action}";
        return builder.Uri;
    }

    private static bool IsPrivateOrLoopback(string host)
    {
        if (host.Equals("localhost", StringComparison.OrdinalIgnoreCase)) return true;
        if (!IPAddress.TryParse(host, out var ip)) return false;
        if (IPAddress.IsLoopback(ip)) return true;
        var b = ip.GetAddressBytes();
        return b.Length == 4 && (b[0] == 10 || b[0] == 127 || (b[0] == 192 && b[1] == 168) || (b[0] == 172 && b[1] is >= 16 and <= 31) || (b[0] == 169 && b[1] == 254));
    }

    private void RequireConnected() { if (!Status.Connected) throw new InvalidOperationException("HTTP 桥接未连接。 "); }
}

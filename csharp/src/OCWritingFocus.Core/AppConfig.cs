using System.Text.Json;
using System.Text.Json.Serialization;

namespace OCWritingFocus.Core;

public sealed class AppConfig
{
    public const int CurrentSchemaVersion = 2;
    public int SchemaVersion { get; set; } = CurrentSchemaVersion;
    public FocusConfig Focus { get; set; } = new();
    public TriggerConfig Trigger { get; set; } = new();
    public DeviceConfig Device { get; set; } = new();
    public SafetyConfig Safety { get; set; } = new();
    public ScopeConfig Scope { get; set; } = new();

    public static AppConfig SafeDefaults() => new();

    public void Validate()
    {
        if (SchemaVersion != CurrentSchemaVersion) throw new InvalidDataException($"不支持的配置版本：{SchemaVersion}");
        RequireRange(Focus.SessionMinutes, 1, 10080, "专注分钟");
        RequireRange(Focus.LeaveSeconds, 1, 86400, "离开等待");
        RequireRange(Focus.IdleSeconds, 1, 86400, "空闲等待");
        RequireOneOf(Trigger.OutputMode, "输出模式", "untilWhitelist", "fixedDuration");
        RequireOneOf(Trigger.OverlapMode, "叠加策略", "restart", "extend");
        RequireOneOf(Trigger.Channel, "输出通道", "both", "A", "B");
        ValidateStrength(Trigger.StrengthA, "A 强度");
        ValidateStrength(Trigger.StrengthB, "B 强度");
        RequireOneOf(Trigger.Waveform, "波形", "constant", "pulse", "ramp", "heartbeat");
        RequireRange(Trigger.WavePeriodMs, 10, 1000, "波形周期");
        RequireRange(Trigger.WaveIntensity, 0, 100, "波形强度");
        RequireRange(Trigger.DurationSeconds, 1, 30, "固定持续时间");
        RequireRange(Trigger.MaxContinuousSeconds, 1, 30, "最长持续时间");
        RequireRange(Trigger.CooldownSeconds, 5, 3600, "冷却时间");
        RequireOneOf(Device.Mode, "设备模式", "http", "ble", "socket");
        RequireOneOf(Device.Socket.Mode, "Socket 模式", "local", "remote");
        RequireRange(Device.Socket.LocalPort, 1, 65535, "Socket 端口");
        foreach (var item in new[] { Safety.HttpLimitA, Safety.HttpLimitB, Safety.SoftLimitA, Safety.SoftLimitB }) RequireRange(item, 0, 200, "安全上限");
        foreach (var item in new[] { Safety.FrequencyBalanceA, Safety.FrequencyBalanceB, Safety.StrengthBalanceA, Safety.StrengthBalanceB }) RequireRange(item, 0, 255, "BF 平衡参数");
    }

    private static void RequireRange(int value, int min, int max, string name)
    {
        if (value < min || value > max) throw new InvalidDataException($"{name}必须位于 {min}–{max}。 ");
    }

    private static void RequireOneOf(string value, string name, params string[] values)
    {
        if (!values.Contains(value)) throw new InvalidDataException($"{name}无效。 ");
    }

    private static void ValidateStrength(int[] value, string name)
    {
        if (value.Length != 2 || value[0] < 0 || value[1] > 200 || value[0] > value[1]) throw new InvalidDataException($"{name}范围无效。 ");
    }
}

public sealed class FocusConfig
{
    public int SessionMinutes { get; set; } = 45;
    public int LeaveSeconds { get; set; } = 300;
    public int IdleSeconds { get; set; } = 600;
}

public sealed class TriggerConfig
{
    public string OutputMode { get; set; } = "fixedDuration";
    public string OverlapMode { get; set; } = "restart";
    public string Channel { get; set; } = "both";
    public int[] StrengthA { get; set; } = [10, 20];
    public int[] StrengthB { get; set; } = [10, 20];
    public string Waveform { get; set; } = "constant";
    public int WavePeriodMs { get; set; } = 30;
    public int WaveIntensity { get; set; } = 20;
    public int DurationSeconds { get; set; } = 1;
    public int MaxContinuousSeconds { get; set; } = 10;
    public int CooldownSeconds { get; set; } = 60;
}

public sealed class DeviceConfig
{
    public string Mode { get; set; } = "http";
    public string HttpEndpoint { get; set; } = "http://127.0.0.1:8080";
    public string BleAddress { get; set; } = "";
    public SocketConfig Socket { get; set; } = new();
}

public sealed class SocketConfig
{
    public string Mode { get; set; } = "local";
    public string LocalHost { get; set; } = "127.0.0.1";
    public int LocalPort { get; set; } = 5678;
    public string RemoteServer { get; set; } = "ws://192.168.1.100:5678";
}

public sealed class SafetyConfig
{
    public int HttpLimitA { get; set; } = 30;
    public int HttpLimitB { get; set; } = 30;
    public int SoftLimitA { get; set; } = 30;
    public int SoftLimitB { get; set; } = 30;
    public int FrequencyBalanceA { get; set; }
    public int FrequencyBalanceB { get; set; }
    public int StrengthBalanceA { get; set; }
    public int StrengthBalanceB { get; set; }
}

public sealed class ScopeConfig
{
    public List<string> Whitelist { get; set; } = [];
    public List<string> Blacklist { get; set; } = [];
}

public static class ConfigStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    public static string DefaultPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "OCWritingFocus", "csharp-config.json");

    public static AppConfig Load(string? path = null)
    {
        path ??= DefaultPath;
        if (!File.Exists(path)) return AppConfig.SafeDefaults();
        var result = JsonSerializer.Deserialize<AppConfig>(File.ReadAllText(path), JsonOptions) ?? throw new InvalidDataException("配置文件为空。 ");
        result.Validate();
        return result;
    }

    public static void Save(AppConfig config, string? path = null)
    {
        path ??= DefaultPath;
        config.SchemaVersion = AppConfig.CurrentSchemaVersion;
        config.Validate();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(config, JsonOptions));
    }
}

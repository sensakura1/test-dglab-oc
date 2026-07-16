namespace OCWritingFocus.Core;

public sealed record OutputProfile(int StrengthA, int StrengthB, string Channel, TimeSpan Duration, TimeSpan MaxContinuous,
    bool HoldUntilWhitelist, bool RestartOnRepeat, string Waveform, int WavePeriodMs, int WaveIntensity);

public sealed record DeviceStatus(bool Connected, string Text, string Source, int ActualA = 0, int ActualB = 0,
    bool Known = false, int LimitA = 0, int LimitB = 0, bool HasLimits = false);

public interface IDeviceAdapter : IAsyncDisposable
{
    DeviceStatus Status { get; }
    Task ConnectAsync(CancellationToken cancellationToken);
    Task ActivateAsync(OutputProfile profile, CancellationToken cancellationToken);
    Task StopAsync(CancellationToken cancellationToken);
    Task DisconnectAsync(CancellationToken cancellationToken);
}

public static class OutputProfiles
{
    public static OutputProfile From(AppConfig config, Random? random = null)
    {
        random ??= Random.Shared;
        var a = random.Next(config.Trigger.StrengthA[0], config.Trigger.StrengthA[1] + 1);
        var b = random.Next(config.Trigger.StrengthB[0], config.Trigger.StrengthB[1] + 1);
        if (config.Trigger.Channel == "A") b = 0;
        if (config.Trigger.Channel == "B") a = 0;
        return new(a, b, config.Trigger.Channel, TimeSpan.FromSeconds(config.Trigger.DurationSeconds),
            TimeSpan.FromSeconds(config.Trigger.MaxContinuousSeconds), config.Trigger.OutputMode == "untilWhitelist",
            config.Trigger.OverlapMode == "restart", config.Trigger.Waveform, config.Trigger.WavePeriodMs, config.Trigger.WaveIntensity);
    }
}

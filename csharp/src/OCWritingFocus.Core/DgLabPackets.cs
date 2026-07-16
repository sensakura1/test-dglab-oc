namespace OCWritingFocus.Core;

public static class DgLabPackets
{
    public static byte[] Safety(SafetyConfig safety) =>
    [
        0xBF, (byte)safety.SoftLimitA, (byte)safety.SoftLimitB,
        (byte)safety.FrequencyBalanceA, (byte)safety.FrequencyBalanceB,
        (byte)safety.StrengthBalanceA, (byte)safety.StrengthBalanceB
    ];

    public static byte[] Output(OutputProfile profile, bool stop = false)
    {
        byte parseMode = stop ? (byte)0x0F : (byte)0;
        var enabledA = !stop && profile.Channel != "B"; var enabledB = !stop && profile.Channel != "A";
        if (enabledA) parseMode |= 0x0C; if (enabledB) parseMode |= 0x03;
        var (frequency, intensity) = Waveform(profile);
        var intensityA = enabledA ? intensity : [101, 101, 101, 101];
        var intensityB = enabledB ? intensity : [101, 101, 101, 101];
        if (stop) { frequency = [10, 10, 10, 10]; intensityA = [0, 0, 0, 0]; intensityB = [0, 0, 0, 0]; }
        return [0xB0, parseMode, enabledA ? (byte)profile.StrengthA : (byte)0, enabledB ? (byte)profile.StrengthB : (byte)0,
            ..frequency, ..intensityA, ..frequency, ..intensityB];
    }

    private static (byte[] Frequency, byte[] Intensity) Waveform(OutputProfile profile)
    {
        var frequency = (byte)Math.Clamp(profile.WavePeriodMs / 10, 10, 100);
        var level = (byte)Math.Clamp(profile.WaveIntensity, 0, 100);
        byte[] intensities = profile.Waveform switch
        {
            "pulse" => [level, 0, level, 0],
            "ramp" => [(byte)(level * .25), (byte)(level * .5), (byte)(level * .75), level],
            "heartbeat" => [level, (byte)(level * .35), 0, (byte)(level * .7)],
            _ => [level, level, level, level]
        };
        return ([frequency, frequency, frequency, frequency], intensities);
    }
}

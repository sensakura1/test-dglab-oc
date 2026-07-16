namespace OCWritingFocus.Core;

public sealed class FocusSession
{
    public bool Running { get; private set; }
    public bool Paused { get; private set; }
    public bool Locked { get; private set; }
    public bool Connected { get; set; }
    public ScopeMatch WindowMatch { get; private set; } = ScopeMatch.Whitelist;
    public int SessionSeconds { get; private set; }
    public int LeftSeconds { get; private set; }
    public int IdleSeconds { get; private set; }
    public bool AwayEpisodeActive { get; private set; }
    public bool EpisodeTriggerSent { get; private set; }
    private bool _idleTriggerSent;

    public FocusSession(FocusConfig config) => SessionSeconds = config.SessionMinutes * 60;

    public void Start(FocusConfig config)
    {
        Running = true; Paused = false; Locked = false;
        SessionSeconds = config.SessionMinutes * 60; LeftSeconds = 0; IdleSeconds = 0;
        AwayEpisodeActive = false; EpisodeTriggerSent = false; _idleTriggerSent = false;
    }

    public void End() { Running = false; Paused = false; LeftSeconds = 0; IdleSeconds = 0; AwayEpisodeActive = false; EpisodeTriggerSent = false; }
    public void TogglePause() { if (Running) Paused = !Paused; }
    public void EmergencyLock() { Locked = true; Running = false; Paused = false; }
    public void Unlock() => Locked = false;

    public (string? Trigger, bool Returned) ApplyWindow(ScopeMatch match)
    {
        WindowMatch = match;
        if (match == ScopeMatch.Whitelist)
        {
            LeftSeconds = 0; AwayEpisodeActive = false; EpisodeTriggerSent = false;
            return (null, true);
        }
        if (!AwayEpisodeActive) { AwayEpisodeActive = true; EpisodeTriggerSent = false; }
        if (match == ScopeMatch.Blacklist)
        {
            LeftSeconds = 0;
            if (Running && !Paused && !Locked && Connected && !EpisodeTriggerSent)
            {
                EpisodeTriggerSent = true;
                return ("黑名单直接触发", false);
            }
        }
        return (null, false);
    }

    public string? Tick(FocusConfig config, int idleSeconds)
    {
        if (!Running || Paused || Locked) return null;
        if (SessionSeconds > 0) SessionSeconds--;
        if (idleSeconds < IdleSeconds) _idleTriggerSent = false;
        IdleSeconds = Math.Max(0, idleSeconds);
        if (WindowMatch is not (ScopeMatch.Whitelist or ScopeMatch.Blacklist)) LeftSeconds++; else LeftSeconds = 0;
        if (AwayEpisodeActive && !EpisodeTriggerSent && LeftSeconds >= config.LeaveSeconds && Connected)
        {
            EpisodeTriggerSent = true;
            return "离开写作范围";
        }
        if (!_idleTriggerSent && IdleSeconds >= config.IdleSeconds && Connected)
        {
            _idleTriggerSent = true;
            return "长时间无输入";
        }
        if (SessionSeconds == 0) { Running = false; return "专注周期结束"; }
        return null;
    }

    public string StatusText => Locked ? "急停锁定" : !Running ? "未开始" : Paused ? "已暂停" : WindowMatch switch
    {
        ScopeMatch.Whitelist => "写作中",
        ScopeMatch.Blacklist => "黑名单命中",
        _ => "离开中"
    };
}

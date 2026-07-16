using OCWritingFocus.Core;

var passed = 0;
Run("安全默认配置有效", () => AppConfig.SafeDefaults().Validate());
Run("黑名单优先于白名单", () => Equal(ScopeMatch.Blacklist, ScopeRules.Classify("editor | OC", ["editor | OC"], ["editor | OC"])));
Run("白名单匹配忽略大小写", () => Equal(ScopeMatch.Whitelist, ScopeRules.Classify("EDITOR | OC", ["editor | oc"], [])));
Run("未匹配窗口被识别", () => Equal(ScopeMatch.Unmatched, ScopeRules.Classify("browser | video", [], [])));
Run("离开达到阈值后触发一次", () =>
{
    var config = new FocusConfig { SessionMinutes = 1, LeaveSeconds = 2, IdleSeconds = 10 };
    var session = new FocusSession(config) { Connected = true }; session.Start(config); session.ApplyWindow(ScopeMatch.Unmatched);
    Equal<string?>(null, session.Tick(config, 0)); Equal("离开写作范围", session.Tick(config, 0)); Equal<string?>(null, session.Tick(config, 0));
});
Run("急停会锁定并停止会话", () => { var c = new FocusConfig(); var s = new FocusSession(c); s.Start(c); s.EmergencyLock(); Equal(false, s.Running); Equal(true, s.Locked); });
Run("输出配置遵循单通道", () => { var c = AppConfig.SafeDefaults(); c.Trigger.Channel = "A"; c.Trigger.StrengthA = [10, 10]; c.Trigger.StrengthB = [20, 20]; var p = OutputProfiles.From(c); Equal(10, p.StrengthA); Equal(0, p.StrengthB); });
Run("蓝牙 BF/B0 数据包结构有效", () => { var c = AppConfig.SafeDefaults(); var p = OutputProfiles.From(c); Equal(7, DgLabPackets.Safety(c.Safety).Length); Equal((byte)0xBF, DgLabPackets.Safety(c.Safety)[0]); Equal(20, DgLabPackets.Output(p).Length); Equal((byte)0xB0, DgLabPackets.Output(p)[0]); });

Console.WriteLine($"C# core self-test passed: {passed}/8");

void Run(string name, Action test)
{
    try { test(); passed++; Console.WriteLine("PASS " + name); }
    catch (Exception ex) { Console.Error.WriteLine("FAIL " + name + ": " + ex.Message); Environment.ExitCode = 1; }
}

static void Equal<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new InvalidOperationException($"expected={expected}, actual={actual}");
}

namespace OCWritingFocus.Core;

public enum ScopeMatch { Unknown, Blacklist, Whitelist, Unmatched }

public static class ScopeRules
{
    public static ScopeMatch Classify(string display, IEnumerable<string> whitelist, IEnumerable<string> blacklist)
    {
        var normalized = display.Trim();
        if (normalized.Length == 0 || normalized.Equals("unknown", StringComparison.OrdinalIgnoreCase)) return ScopeMatch.Unknown;
        if (blacklist.Any(x => normalized.Equals(x.Trim(), StringComparison.OrdinalIgnoreCase))) return ScopeMatch.Blacklist;
        if (whitelist.Any(x => normalized.Equals(x.Trim(), StringComparison.OrdinalIgnoreCase))) return ScopeMatch.Whitelist;
        return ScopeMatch.Unmatched;
    }

    public static string ToDisplay(this ScopeMatch match) => match switch
    {
        ScopeMatch.Blacklist => "黑名单",
        ScopeMatch.Whitelist => "白名单",
        ScopeMatch.Unknown => "无法识别",
        _ => "未匹配"
    };
}

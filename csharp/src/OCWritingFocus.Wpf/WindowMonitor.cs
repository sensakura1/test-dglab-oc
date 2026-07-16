using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace OCWritingFocus.Wpf;

internal sealed record WindowInfo(string Process, string Title)
{
    public string Display => string.IsNullOrWhiteSpace(Title) ? Process : $"{Process} | {Title}";
}

internal static class WindowMonitor
{
    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool GetLastInputInfo(ref LastInputInfo info);

    [StructLayout(LayoutKind.Sequential)] private struct LastInputInfo { public uint Size; public uint Time; }

    public static WindowInfo Foreground() => Read(GetForegroundWindow());

    public static IReadOnlyList<WindowInfo> VisibleWindows()
    {
        var result = new Dictionary<string, WindowInfo>(StringComparer.OrdinalIgnoreCase);
        EnumWindows((hwnd, _) => { if (IsWindowVisible(hwnd) && GetWindowTextLength(hwnd) > 0) { var item = Read(hwnd); if (!string.IsNullOrWhiteSpace(item.Title)) result[item.Display] = item; } return true; }, IntPtr.Zero);
        return result.Values.OrderBy(x => x.Display, StringComparer.CurrentCultureIgnoreCase).ToArray();
    }

    public static int IdleSeconds
    {
        get { var info = new LastInputInfo { Size = (uint)Marshal.SizeOf<LastInputInfo>() }; return GetLastInputInfo(ref info) ? (int)((Environment.TickCount64 - info.Time) / 1000) : 0; }
    }

    private static WindowInfo Read(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return new("unknown", "");
        var text = new StringBuilder(GetWindowTextLength(hwnd) + 1); GetWindowText(hwnd, text, text.Capacity);
        GetWindowThreadProcessId(hwnd, out var pid);
        try { return new(Process.GetProcessById((int)pid).ProcessName, text.ToString()); } catch { return new("unknown", text.ToString()); }
    }
}

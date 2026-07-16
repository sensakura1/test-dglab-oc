using System.Windows;

namespace OCWritingFocus.Wpf;

public partial class ChannelMonitorWindow : Window
{
    public ChannelMonitorWindow() => InitializeComponent();

    public void Update(string a, string b, string duration, string remaining, string source)
    {
        FloatingStrengthAValue.Text = a;
        FloatingStrengthBValue.Text = b;
        FloatingDurationValue.Text = duration;
        FloatingRemainingValue.Text = remaining;
        FloatingSourceValue.Text = source;
    }
}

public partial class WindowMonitorWindow : Window
{
    public WindowMonitorWindow() => InitializeComponent();

    public void Update(string display, string match)
    {
        FloatingWindowDisplayValue.Text = display;
        FloatingWindowMatchValue.Text = match;
    }
}

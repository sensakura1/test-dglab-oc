using Microsoft.Win32;
using OCWritingFocus.Core;
using QRCoder;
using System.Collections.ObjectModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace OCWritingFocus.Wpf;

public partial class MainWindow : Window
{
    private AppConfig _config;
    private FocusSession _session;
    private IDeviceAdapter? _device;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly DispatcherTimer _floatingTimer = new() { Interval = TimeSpan.FromMilliseconds(200) };
    private readonly ObservableCollection<string> _logs = [];
    private ChannelMonitorWindow? _channelMonitor;
    private WindowMonitorWindow? _windowMonitor;
    private bool _outputActive;
    private DateTime _outputEnd;
    private OutputProfile? _activeProfile;

    public MainWindow()
    {
        InitializeComponent();
        try { _config = ConfigStore.Load(); }
        catch (Exception ex) { _config = AppConfig.SafeDefaults(); Loaded += (_, _) => AddLog("配置加载失败，已使用安全默认值：" + ex.Message); }
        _session = new FocusSession(_config.Focus);
        LogList.ItemsSource = _logs;
        AttachEvents();
        ApplyConfigToUi();
        RefreshWindowPicker();
        ShowPage("dashboard");
        RefreshForeground();
        UpdateView();
        _timer.Tick += Timer_Tick;
        _floatingTimer.Tick += (_, _) => UpdateFloatingMonitors();
        _timer.Start();
        _floatingTimer.Start();
        AddLog("C# WPF 桌面应用已启动");
        Closing += MainWindow_Closing;
    }

    private void AttachEvents()
    {
        NavDashboardButton.Click += (_, _) => ShowPage("dashboard");
        NavScopeButton.Click += (_, _) => ShowPage("scope");
        NavTriggerButton.Click += (_, _) => ShowPage("trigger");
        NavDeviceButton.Click += (_, _) => ShowPage("device");
        NavLogsButton.Click += (_, _) => ShowPage("logs");
        StartButton.Click += Start_Click;
        PauseButton.Click += Pause_Click;
        EndButton.Click += End_Click;
        UnlockButton.Click += Unlock_Click;
        ManualTestButton.Click += ManualTest_Click;
        EmergencyButton.Click += Emergency_Click;
        FloatingMonitorButton.Click += OpenChannelMonitor_Click;
        FloatingWindowMonitorButton.Click += OpenWindowMonitor_Click;
        RefreshWindowListButton.Click += (_, _) => RefreshWindowPicker();
        AddWhitelistButton.Click += (_, _) => AddScope(_config.Scope.Whitelist, "白名单");
        AddBlacklistButton.Click += (_, _) => AddScope(_config.Scope.Blacklist, "黑名单");
        RemoveWhitelistButton.Click += (_, _) => RemoveScope(_config.Scope.Whitelist, WhitelistList, "白名单");
        RemoveBlacklistButton.Click += (_, _) => RemoveScope(_config.Scope.Blacklist, BlacklistList, "黑名单");
        ConnectButton.Click += Connect_Click;
        ApplySafetyButton.Click += ApplySafety_Click;
        DisconnectButton.Click += async (_, _) => await DisconnectDeviceAsync(true);
        StopButton.Click += async (_, _) => await StopOutputAsync("已手动停止 A/B");
        DeviceModeCombo.SelectionChanged += (_, _) => UpdateDeviceModeUi();
        SocketServerModeCombo.SelectionChanged += (_, _) => UpdateSocketModeUi();
        ImportConfigButton.Click += ImportConfig_Click;
        ExportConfigButton.Click += ExportConfig_Click;
        ResetSafeConfigButton.Click += ResetConfig_Click;
        ClearLogsButton.Click += (_, _) => _logs.Clear();
    }

    private void ShowPage(string page)
    {
        DashboardPage.Visibility = Visibility.Collapsed;
        SettingsPage.Visibility = Visibility.Collapsed;
        SessionControlPanel.Visibility = Visibility.Collapsed;
        TriggerStrategyPanel.Visibility = Visibility.Collapsed;
        CoyoteOutputPanel.Visibility = Visibility.Collapsed;
        DeviceSafetyPanel.Visibility = Visibility.Collapsed;
        LowerPages.Visibility = Visibility.Collapsed;
        ScopeRulesPanel.Visibility = Visibility.Collapsed;
        LogsPanel.Visibility = Visibility.Collapsed;
        foreach (var button in new[] { NavDashboardButton, NavScopeButton, NavTriggerButton, NavDeviceButton, NavLogsButton }) button.Background = Brushes.Transparent;

        Button active;
        switch (page)
        {
            case "scope":
                LowerPages.Visibility = Visibility.Visible; ScopeRulesPanel.Visibility = Visibility.Visible;
                Grid.SetColumn(ScopeRulesPanel, 0); Grid.SetColumnSpan(ScopeRulesPanel, 2);
                PageEyebrowValue.Text = "FOCUS SESSION  /  SCOPE RULES"; PageTitleValue.Text = "范围规则"; active = NavScopeButton; RefreshWindowPicker(); break;
            case "trigger":
                SettingsPage.Visibility = Visibility.Visible; SessionControlPanel.Visibility = Visibility.Visible; TriggerStrategyPanel.Visibility = Visibility.Visible; CoyoteOutputPanel.Visibility = Visibility.Visible;
                PageEyebrowValue.Text = "FOCUS SESSION  /  TRIGGER PROFILE"; PageTitleValue.Text = "触发设置"; active = NavTriggerButton; break;
            case "device":
                SettingsPage.Visibility = Visibility.Visible; DeviceSafetyPanel.Visibility = Visibility.Visible;
                PageEyebrowValue.Text = "FOCUS SESSION  /  DEVICE SAFETY"; PageTitleValue.Text = "设备与安全"; active = NavDeviceButton; break;
            case "logs":
                LowerPages.Visibility = Visibility.Visible; LogsPanel.Visibility = Visibility.Visible;
                Grid.SetColumn(LogsPanel, 0); Grid.SetColumnSpan(LogsPanel, 2);
                PageEyebrowValue.Text = "FOCUS SESSION  /  EVENT LOG"; PageTitleValue.Text = "日志"; active = NavLogsButton; break;
            default:
                DashboardPage.Visibility = Visibility.Visible;
                PageEyebrowValue.Text = "FOCUS SESSION  /  DASHBOARD"; PageTitleValue.Text = "控制台"; active = NavDashboardButton; break;
        }
        active.Background = new SolidColorBrush(Color.FromRgb(45, 140, 255));
        MainScrollViewer.ScrollToTop();
    }

    private async void Timer_Tick(object? sender, EventArgs e)
    {
        var match = RefreshForeground();
        _session.Connected = _device?.Status.Connected == true;
        var (trigger, returned) = _session.ApplyWindow(match);
        if (returned && _outputActive && _activeProfile?.HoldUntilWhitelist == true) await StopOutputAsync("返回白名单，输出已停止");
        if (trigger is not null) await TriggerAsync(trigger);
        trigger = _session.Tick(_config.Focus, WindowMonitor.IdleSeconds);
        if (trigger is not null) await TriggerAsync(trigger);
        if (_outputActive && DateTime.UtcNow >= _outputEnd) await StopOutputAsync("已达到输出持续上限");
        UpdateView();
    }

    private ScopeMatch RefreshForeground()
    {
        var display = WindowMonitor.Foreground().Display;
        var match = ScopeRules.Classify(display, _config.Scope.Whitelist, _config.Scope.Blacklist);
        CurrentWindowInput.Text = display;
        CurrentWindowMatchValue.Text = match.ToDisplay();
        _windowMonitor?.Update(display, match.ToDisplay());
        return match;
    }

    private void Start_Click(object sender, RoutedEventArgs e)
    {
        if (!TryCaptureConfig()) return;
        _session.Start(_config.Focus); AddLog("专注周期已开始"); UpdateView();
    }
    private void Pause_Click(object sender, RoutedEventArgs e) { _session.TogglePause(); AddLog(_session.Paused ? "专注已暂停" : "专注已恢复"); UpdateView(); }
    private async void End_Click(object sender, RoutedEventArgs e) { await StopOutputAsync(null); _session.End(); AddLog("专注周期已结束"); UpdateView(); }
    private async void Emergency_Click(object sender, RoutedEventArgs e) { await StopOutputAsync(null); _session.EmergencyLock(); AddLog("急停已执行，进入安全锁定"); UpdateView(); }
    private void Unlock_Click(object sender, RoutedEventArgs e) { _session.Unlock(); AddLog("安全锁定已解除"); UpdateView(); }
    private async void ManualTest_Click(object sender, RoutedEventArgs e) => await TriggerAsync("手动测试");

    private async Task TriggerAsync(string reason)
    {
        if (_session.Locked) { AddLog("触发被拦截：安全锁定"); return; }
        if (_device?.Status.Connected != true) { AddLog("触发被拦截：设备未连接"); return; }
        if (!_device.Status.HasLimits) { AddLog("触发被拦截：尚未取得 A/B 安全上限"); return; }
        var profile = OutputProfiles.From(_config);
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(6));
            await _device.ActivateAsync(profile, timeout.Token);
            _activeProfile = profile; _outputActive = true;
            var duration = profile.HoldUntilWhitelist ? profile.MaxContinuous : profile.Duration;
            _outputEnd = DateTime.UtcNow + duration;
            var waveformName = _config.Device.Mode == "socket" ? "DG-Lab App" : profile.Waveform;
            AddLog($"{reason}：通道 {profile.Channel}，A={profile.StrengthA} B={profile.StrengthB}，波形 {waveformName}，{duration.TotalSeconds:0} 秒");
        }
        catch (Exception ex) { AddLog("设备触发失败：" + ex.Message); }
        UpdateView();
    }

    private async Task StopOutputAsync(string? message)
    {
        if (_device?.Status.Connected == true)
        {
            try { using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5)); await _device.StopAsync(timeout.Token); }
            catch (Exception ex) { AddLog("设备停止失败：" + ex.Message); }
        }
        _outputActive = false; _activeProfile = null; _outputEnd = default;
        if (message is not null) AddLog(message);
        UpdateView();
    }

    private async void Connect_Click(object sender, RoutedEventArgs e)
    {
        if (!TryCaptureConfig()) return;
        await DisconnectDeviceAsync(false);
        _device = _config.Device.Mode switch
        {
            "ble" => new BleDeviceAdapter(_config.Device.BleAddress, _config.Safety),
            "socket" => new SocketDeviceAdapter(_config.Device.Socket),
            _ => new HttpDeviceAdapter(_config.Device.HttpEndpoint, _config.Safety.HttpLimitA, _config.Safety.HttpLimitB)
        };
        AddLog("正在连接设备…");
        try { using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(8)); await _device.ConnectAsync(timeout.Token); AddLog("设备连接流程已启动"); }
        catch (Exception ex) { AddLog("设备连接失败：" + ex.Message); }
        UpdateView();
    }

    private async void ApplySafety_Click(object sender, RoutedEventArgs e)
    {
        if (_device is not BleDeviceAdapter ble) { AddLog("BF 参数仅能在蓝牙 V3 已连接时应用"); return; }
        try { await ble.ApplySafetyAsync(CancellationToken.None); AddLog("BF 安全参数已重新应用"); }
        catch (Exception ex) { AddLog("BF 参数写入失败：" + ex.Message); }
    }

    private async Task DisconnectDeviceAsync(bool log)
    {
        if (_device is not null)
        {
            try { using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5)); await _device.DisconnectAsync(timeout.Token); await _device.DisposeAsync(); }
            catch (Exception ex) { if (log) AddLog("断开设备时发生错误：" + ex.Message); }
        }
        _device = null; _outputActive = false; _session.Connected = false;
        ClearSocketUi();
        if (log) AddLog("设备连接已断开");
        UpdateView();
    }

    private void UpdateDeviceModeUi()
    {
        if (!IsInitialized) return;
        var mode = Selected(DeviceModeCombo, "http", "ble", "socket");
        _config.Device.Mode = mode;
        HttpConnectionPage.Visibility = mode == "http" ? Visibility.Visible : Visibility.Collapsed;
        BleConnectionPage.Visibility = mode == "ble" ? Visibility.Visible : Visibility.Collapsed;
        SocketConnectionPage.Visibility = mode == "socket" ? Visibility.Visible : Visibility.Collapsed;
        ApplySafetyButton.Visibility = mode == "ble" ? Visibility.Visible : Visibility.Collapsed;
        UpdateWaveformUi(CurrentStatus());
        ConnectButton.Content = mode switch { "ble" => "连接并应用安全参数", "socket" => SocketServerModeCombo.SelectedIndex == 0 ? "启动本地服务器并生成二维码" : "连接外部服务器并生成二维码", _ => "连接 HTTP 桥接" };
    }

    private void UpdateSocketModeUi()
    {
        if (!IsInitialized) return;
        var local = SocketServerModeCombo.SelectedIndex == 0;
        _config.Device.Socket.Mode = local ? "local" : "remote";
        LocalSocketSettings.Visibility = local ? Visibility.Visible : Visibility.Collapsed;
        RemoteSocketSettings.Visibility = local ? Visibility.Collapsed : Visibility.Visible;
        if (DeviceModeCombo.SelectedIndex == 2) ConnectButton.Content = local ? "启动本地服务器并生成二维码" : "连接外部服务器并生成二维码";
    }

    private void RefreshWindowPicker()
    {
        WindowPickerCombo.ItemsSource = WindowMonitor.VisibleWindows().Select(x => x.Display).ToArray();
        if (WindowPickerCombo.Items.Count > 0) WindowPickerCombo.SelectedIndex = 0;
    }

    private void AddScope(List<string> list, string name)
    {
        if (WindowPickerCombo.SelectedItem is not string value || list.Contains(value, StringComparer.OrdinalIgnoreCase)) return;
        list.Add(value); RefreshScopeLists(); AddLog($"已添加{name}：{value}"); RefreshForeground();
    }
    private void RemoveScope(List<string> list, ListBox box, string name)
    {
        if (box.SelectedItem is not string value) return;
        list.Remove(value); RefreshScopeLists(); AddLog($"已删除{name}：{value}"); RefreshForeground();
    }
    private void RefreshScopeLists()
    {
        WhitelistList.ItemsSource = null; WhitelistList.ItemsSource = _config.Scope.Whitelist;
        BlacklistList.ItemsSource = null; BlacklistList.ItemsSource = _config.Scope.Blacklist;
    }

    private bool TryCaptureConfig()
    {
        try
        {
            _config.Focus.SessionMinutes = ParseInt(FocusMinutesInput, 45, 1, 10080);
            _config.Focus.LeaveSeconds = ParseInt(LeaveInput, 300, 1, 86400);
            _config.Focus.IdleSeconds = ParseInt(IdleInput, 600, 1, 86400);
            _config.Trigger.OutputMode = Selected(OutputModeCombo, "untilWhitelist", "fixedDuration");
            _config.Trigger.OverlapMode = Selected(OverlapModeCombo, "restart", "extend");
            _config.Trigger.Channel = Selected(ChannelModeCombo, "both", "A", "B");
            _config.Trigger.StrengthA = ParseRange(StrengthARangeInput); _config.Trigger.StrengthB = ParseRange(StrengthBRangeInput);
            _config.Trigger.Waveform = Selected(WaveformCombo, "constant", "pulse", "ramp", "heartbeat");
            _config.Trigger.WavePeriodMs = ParseInt(WavePeriodInput, 30, 10, 1000); _config.Trigger.WaveIntensity = ParseInt(WaveIntensityInput, 20, 0, 100);
            _config.Trigger.DurationSeconds = ParseInt(DurationInput, 1, 1, 30); _config.Trigger.MaxContinuousSeconds = ParseInt(MaxContinuousInput, 10, 1, 30); _config.Trigger.CooldownSeconds = ParseInt(HoldCooldownInput, 60, 5, 3600);
            _config.Device.Mode = Selected(DeviceModeCombo, "http", "ble", "socket"); _config.Device.HttpEndpoint = HttpEndpointInput.Text.Trim(); _config.Device.BleAddress = BleAddressInput.Text.Trim();
            _config.Device.Socket.Mode = Selected(SocketServerModeCombo, "local", "remote"); _config.Device.Socket.LocalHost = LocalSocketHostInput.Text.Trim(); _config.Device.Socket.LocalPort = ParseInt(LocalSocketPortInput, 5678, 1, 65535); _config.Device.Socket.RemoteServer = SocketServerInput.Text.Trim();
            _config.Safety.HttpLimitA = ParseInt(HttpLimitAInput, 30, 0, 200); _config.Safety.HttpLimitB = ParseInt(HttpLimitBInput, 30, 0, 200); _config.Safety.SoftLimitA = ParseInt(SoftLimitAInput, 30, 0, 200); _config.Safety.SoftLimitB = ParseInt(SoftLimitBInput, 30, 0, 200);
            _config.Safety.FrequencyBalanceA = ParseInt(FrequencyBalanceAInput, 0, 0, 255); _config.Safety.FrequencyBalanceB = ParseInt(FrequencyBalanceBInput, 0, 0, 255); _config.Safety.StrengthBalanceA = ParseInt(StrengthBalanceAInput, 0, 0, 255); _config.Safety.StrengthBalanceB = ParseInt(StrengthBalanceBInput, 0, 0, 255);
            _config.Validate(); return true;
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "配置无效", MessageBoxButton.OK, MessageBoxImage.Warning); return false; }
    }

    private void ApplyConfigToUi()
    {
        FocusMinutesInput.Text = _config.Focus.SessionMinutes.ToString(); LeaveInput.Text = _config.Focus.LeaveSeconds.ToString(); IdleInput.Text = _config.Focus.IdleSeconds.ToString();
        SetSelected(OutputModeCombo, _config.Trigger.OutputMode, "untilWhitelist", "fixedDuration"); SetSelected(OverlapModeCombo, _config.Trigger.OverlapMode, "restart", "extend"); SetSelected(ChannelModeCombo, _config.Trigger.Channel, "both", "A", "B"); SetSelected(WaveformCombo, _config.Trigger.Waveform, "constant", "pulse", "ramp", "heartbeat");
        StrengthARangeInput.Text = string.Join('-', _config.Trigger.StrengthA); StrengthBRangeInput.Text = string.Join('-', _config.Trigger.StrengthB); WavePeriodInput.Text = _config.Trigger.WavePeriodMs.ToString(); WaveIntensityInput.Text = _config.Trigger.WaveIntensity.ToString(); DurationInput.Text = _config.Trigger.DurationSeconds.ToString(); MaxContinuousInput.Text = _config.Trigger.MaxContinuousSeconds.ToString(); HoldCooldownInput.Text = _config.Trigger.CooldownSeconds.ToString();
        SetSelected(DeviceModeCombo, _config.Device.Mode, "http", "ble", "socket"); HttpEndpointInput.Text = _config.Device.HttpEndpoint; BleAddressInput.Text = _config.Device.BleAddress; SetSelected(SocketServerModeCombo, _config.Device.Socket.Mode, "local", "remote"); LocalSocketHostInput.Text = _config.Device.Socket.LocalHost; LocalSocketPortInput.Text = _config.Device.Socket.LocalPort.ToString(); SocketServerInput.Text = _config.Device.Socket.RemoteServer;
        HttpLimitAInput.Text = _config.Safety.HttpLimitA.ToString(); HttpLimitBInput.Text = _config.Safety.HttpLimitB.ToString(); SoftLimitAInput.Text = _config.Safety.SoftLimitA.ToString(); SoftLimitBInput.Text = _config.Safety.SoftLimitB.ToString(); FrequencyBalanceAInput.Text = _config.Safety.FrequencyBalanceA.ToString(); FrequencyBalanceBInput.Text = _config.Safety.FrequencyBalanceB.ToString(); StrengthBalanceAInput.Text = _config.Safety.StrengthBalanceA.ToString(); StrengthBalanceBInput.Text = _config.Safety.StrengthBalanceB.ToString();
        RefreshScopeLists(); UpdateSocketModeUi(); UpdateDeviceModeUi();
    }

    private void ImportConfig_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Title = "导入桌面配置", Filter = "JSON 配置文件 (*.json)|*.json|所有文件 (*.*)|*.*" };
        if (dialog.ShowDialog(this) != true) return;
        try { _config = ConfigStore.Load(dialog.FileName); _session = new FocusSession(_config.Focus); ApplyConfigToUi(); AddLog("配置已导入：" + dialog.FileName); }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "配置导入失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }
    private void ExportConfig_Click(object sender, RoutedEventArgs e)
    {
        if (!TryCaptureConfig()) return;
        var dialog = new SaveFileDialog { Title = "导出桌面配置", Filter = "JSON 配置文件 (*.json)|*.json", FileName = "oc-writing-focus-config.json" };
        if (dialog.ShowDialog(this) != true) return;
        try { ConfigStore.Save(_config, dialog.FileName); AddLog("配置已导出：" + dialog.FileName); }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "配置导出失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }
    private async void ResetConfig_Click(object sender, RoutedEventArgs e) { await DisconnectDeviceAsync(false); _config = AppConfig.SafeDefaults(); _session = new FocusSession(_config.Focus); ApplyConfigToUi(); AddLog("已恢复安全默认配置"); }

    private void OpenChannelMonitor_Click(object sender, RoutedEventArgs e)
    {
        if (_channelMonitor is not null) { _channelMonitor.Close(); return; }
        _channelMonitor = new ChannelMonitorWindow();
        _channelMonitor.Closed += (_, _) => { _channelMonitor = null; FloatingMonitorButton.Content = "通道悬浮"; };
        FloatingMonitorButton.Content = "关闭通道"; UpdateFloatingMonitors(); _channelMonitor.Show();
    }
    private void OpenWindowMonitor_Click(object sender, RoutedEventArgs e)
    {
        if (_windowMonitor is not null) { _windowMonitor.Close(); return; }
        _windowMonitor = new WindowMonitorWindow();
        _windowMonitor.Closed += (_, _) => { _windowMonitor = null; FloatingWindowMonitorButton.Content = "窗口悬浮"; };
        FloatingWindowMonitorButton.Content = "关闭窗口"; RefreshForeground(); _windowMonitor.Show();
    }
    private void UpdateFloatingMonitors()
    {
        if (_channelMonitor is null) return;
        var status = CurrentStatus();
        var a = status.Known ? status.ActualA.ToString() : "--"; var b = status.Known ? status.ActualB.ToString() : "--";
        var duration = _activeProfile is null ? _config.Trigger.DurationSeconds : (_activeProfile.HoldUntilWhitelist ? _activeProfile.MaxContinuous.TotalSeconds : _activeProfile.Duration.TotalSeconds);
        var remaining = _outputActive ? $"剩余时间：{Math.Max(0, (_outputEnd - DateTime.UtcNow).TotalSeconds):0.0} 秒" : "剩余时间：未输出";
        _channelMonitor.Update(a, b, $"本次持续：{duration:0} 秒", remaining, status.Source);
    }

    private void UpdateView()
    {
        var status = CurrentStatus();
        StatusValue.Text = _session.StatusText; SessionValue.Text = Format(_session.SessionSeconds); LeftValue.Text = Format(_session.LeftSeconds); DistractionValue.Text = "00:00"; IdleValue.Text = Format(_session.IdleSeconds);
        DeviceValue.Text = status.Text;
        DeviceBadge.Text = _config.Device.Mode switch
        {
            "ble" => status.Connected ? "蓝牙 V3 直连" : "蓝牙未连接",
            "socket" => status.Connected ? "Socket 控制协议" : status.Text.Contains("等待 App") ? "Socket 已注册" : "Socket 未连接",
            _ => status.Connected ? "真实设备桥接" : "真实桥接未连接"
        };
        ActualStrengthValue.Text = status.Known ? $"A {status.ActualA}  |  B {status.ActualB}" : "A --  |  B --"; ActualStrengthSource.Text = status.Source;
        LockBadge.Text = _session.Locked ? "已锁定" : "未锁定"; LockBadgeBorder.Background = new SolidColorBrush(_session.Locked ? Color.FromRgb(165, 42, 42) : Color.FromRgb(37, 56, 74)); UnlockButton.IsEnabled = _session.Locked;
        if (_device is SocketDeviceAdapter socket)
        {
            SocketBindStatusText.Text = status.Text;
            SocketAppLimitsText.Text = status.HasLimits ? $"当前 A={status.ActualA} / 上限 {status.LimitA}；B={status.ActualB} / 上限 {status.LimitB}（来自 App）" : "等待 App 上报 A/B 强度上限；未上报前禁止输出";
            if (!string.IsNullOrWhiteSpace(socket.QrText) && SocketManualAddressText.Text != socket.QrText) SetSocketQr(socket.QrText);
        }
        UpdateWaveformUi(status);
        UpdateFloatingMonitors();
    }

    private void UpdateWaveformUi(DeviceStatus status)
    {
        var socketManaged = _config.Device.Mode == "socket";
        StrengthARangeInput.IsReadOnly = false;
        StrengthBRangeInput.IsReadOnly = false;
        ChannelModeCombo.IsEnabled = true;
        WaveformCombo.Visibility = Visibility.Collapsed;
        WaveformCombo.IsEnabled = false;
        CurrentWaveformText.Visibility = Visibility.Visible;
        CurrentWaveformText.Text = socketManaged ? "App 当前波形（协议未提供具体名称）" : "不支持";
        WavePeriodInput.IsReadOnly = socketManaged;
        WaveIntensityInput.IsReadOnly = socketManaged;
        DurationInput.IsEnabled = true;
        SocketOutputModeText.Visibility = socketManaged ? Visibility.Visible : Visibility.Collapsed;
        if (socketManaged)
        {
            SocketOutputModeText.Text = status.HasLimits
                ? $"Socket：强度和持续时间使用本软件设置；波形由 App 决定。App 安全上限 A={status.LimitA}，B={status.LimitB}"
                : "Socket：强度和持续时间使用本软件设置；波形由 App 决定。等待 App 上报安全上限，收到前禁止输出";
        }
    }

    private DeviceStatus CurrentStatus() => _device?.Status ?? _config.Device.Mode switch
    {
        "ble" => new DeviceStatus(false, "蓝牙设备未连接", "未连接", LimitA: _config.Safety.SoftLimitA, LimitB: _config.Safety.SoftLimitB, HasLimits: true),
        "socket" => new DeviceStatus(false, "Socket 未连接", "Socket 未连接"),
        _ => new DeviceStatus(false, "真实桥接未连接", "未连接", LimitA: _config.Safety.HttpLimitA, LimitB: _config.Safety.HttpLimitB, HasLimits: true)
    };

    private void SetSocketQr(string manualAddress)
    {
        var qrText = $"https://www.dungeon-lab.com/app-download.php#DGLAB-SOCKET#{manualAddress}";
        SocketManualAddressText.Text = manualAddress; SocketQrContentText.Text = qrText;
        using var generator = new QRCodeGenerator(); using var data = generator.CreateQrCode(qrText, QRCodeGenerator.ECCLevel.M); using var png = new PngByteQRCode(data); using var stream = new MemoryStream(png.GetGraphic(6));
        var bitmap = new BitmapImage(); bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.StreamSource = stream; bitmap.EndInit(); bitmap.Freeze();
        SocketQrImage.Source = bitmap; SocketQrPlaceholder.Visibility = Visibility.Collapsed;
    }
    private void ClearSocketUi()
    {
        SocketManualAddressText.Text = ""; SocketQrContentText.Text = ""; SocketQrImage.Source = null; SocketQrPlaceholder.Visibility = Visibility.Visible;
        SocketBindStatusText.Text = "未连接服务器"; SocketAppLimitsText.Text = "等待 App 上报 A/B 强度上限；未上报前禁止输出";
    }

    private void AddLog(string message) { _logs.Insert(0, $"[{DateTime.Now:HH:mm:ss}] {message}"); while (_logs.Count > 80) _logs.RemoveAt(_logs.Count - 1); }

    private async void MainWindow_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        _timer.Stop(); _floatingTimer.Stop(); _channelMonitor?.Close(); _windowMonitor?.Close();
        await DisconnectDeviceAsync(false); if (TryCaptureConfig()) try { ConfigStore.Save(_config); } catch { }
    }

    private static int ParseInt(TextBox box, int fallback, int min, int max) => Math.Clamp(int.TryParse(box.Text.Trim(), out var value) ? value : fallback, min, max);
    private static int[] ParseRange(TextBox box)
    {
        var parts = box.Text.Split(['-', '–', ',', '，'], StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length != 2 || !int.TryParse(parts[0], out var low) || !int.TryParse(parts[1], out var high) || low < 0 || high > 200 || low > high) throw new InvalidDataException($"强度范围“{box.Text}”无效，应为 0-200 范围内的“最小-最大”。 ");
        return [low, high];
    }
    private static string Selected(ComboBox box, params string[] values) => box.SelectedIndex >= 0 && box.SelectedIndex < values.Length ? values[box.SelectedIndex] : values[0];
    private static void SetSelected(ComboBox box, string value, params string[] values) { var index = Array.IndexOf(values, value); box.SelectedIndex = index < 0 ? 0 : index; }
    private static string Format(int seconds) => $"{Math.Max(0, seconds) / 60:00}:{Math.Max(0, seconds) % 60:00}";
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Web.Extensions
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -ReferencedAssemblies @("System.dll", "System.Core.dll", "System.Web.Extensions.dll") -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;

public static class NativeWindowApi
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO
    {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO inputInfo);

    public static uint GetIdleMilliseconds()
    {
        LASTINPUTINFO inputInfo = new LASTINPUTINFO();
        inputInfo.cbSize = (uint)Marshal.SizeOf(inputInfo);
        if (!GetLastInputInfo(ref inputInfo))
        {
            return 0;
        }
        return unchecked((uint)Environment.TickCount - inputInfo.dwTime);
    }
}

public sealed class LocalDglabSocketServer : IDisposable
{
    private readonly object sync = new object();
    private readonly JavaScriptSerializer json = new JavaScriptSerializer();
    private TcpListener listener;
    private TcpClient appClient;
    private NetworkStream appStream;
    private Thread acceptThread;
    private Timer safetyTimer;
    private volatile bool stopping;

    public string ClientId { get; private set; }
    public string TargetId { get; private set; }
    public string LastError { get; private set; }
    public bool IsRunning { get; private set; }
    public bool IsBound { get; private set; }
    public bool HasAppLimits { get; private set; }
    public int AppStrengthA { get; private set; }
    public int AppStrengthB { get; private set; }
    public int AppLimitA { get; private set; }
    public int AppLimitB { get; private set; }
    public int StrengthUpdateCount { get; private set; }
    public int Port { get; private set; }
    public int WatchdogStopCount { get { return watchdogStopCount; } }
    public bool LastWatchdogStopSucceeded { get; private set; }

    public LocalDglabSocketServer()
    {
        ClientId = Guid.NewGuid().ToString();
        TargetId = "";
        LastError = "";
        LastWatchdogStopSucceeded = true;
    }

    public void Start(int port)
    {
        Start("127.0.0.1", port);
    }

    public void Start(string bindAddress, int port)
    {
        if (IsRunning) throw new InvalidOperationException("Server is already running.");
        IPAddress address;
        if (string.Equals(bindAddress, "localhost", StringComparison.OrdinalIgnoreCase)) address = IPAddress.Loopback;
        else if (!IPAddress.TryParse(bindAddress, out address)) throw new ArgumentException("A numeric local bind address is required.", "bindAddress");
        Port = port;
        stopping = false;
        listener = new TcpListener(address, port);
        listener.Start();
        IsRunning = true;
        acceptThread = new Thread(AcceptLoop);
        acceptThread.IsBackground = true;
        acceptThread.Name = "DG-Lab Local Socket Server";
        acceptThread.Start();
    }

    private void AcceptLoop()
    {
        while (!stopping)
        {
            try
            {
                TcpClient client = listener.AcceptTcpClient();
                Thread worker = new Thread(() => HandleClient(client));
                worker.IsBackground = true;
                worker.Start();
            }
            catch (SocketException ex)
            {
                if (!stopping) LastError = ex.Message;
            }
            catch (ObjectDisposedException) { break; }
        }
    }

    private void HandleClient(TcpClient client)
    {
        try
        {
            NetworkStream stream = client.GetStream();
            string request = ReadHttpRequest(stream);
            string[] requestLines = request.Split(new[] { "\r\n" }, StringSplitOptions.None);
            string expectedRequestLine = "GET /" + ClientId + " HTTP/1.1";
            if (requestLines.Length == 0 || !string.Equals(requestLines[0], expectedRequestLine, StringComparison.Ordinal))
                throw new InvalidDataException("Invalid WebSocket registration path.");
            string upgrade = GetHeader(request, "Upgrade");
            string connection = GetHeader(request, "Connection");
            if (!string.Equals(upgrade, "websocket", StringComparison.OrdinalIgnoreCase) ||
                string.IsNullOrWhiteSpace(connection) || connection.IndexOf("Upgrade", StringComparison.OrdinalIgnoreCase) < 0)
                throw new InvalidDataException("Invalid WebSocket upgrade request.");
            string key = GetHeader(request, "Sec-WebSocket-Key");
            if (string.IsNullOrWhiteSpace(key)) throw new InvalidDataException("Missing Sec-WebSocket-Key.");
            string accept;
            using (SHA1 sha1 = SHA1.Create())
            {
                byte[] hash = sha1.ComputeHash(Encoding.ASCII.GetBytes(key.Trim() + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"));
                accept = Convert.ToBase64String(hash);
            }
            string response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n";
            byte[] responseBytes = Encoding.ASCII.GetBytes(response);
            stream.Write(responseBytes, 0, responseBytes.Length);

            lock (sync)
            {
                if (appClient != null) { try { appClient.Close(); } catch { } }
                appClient = client;
                appClient.SendTimeout = 1000;
                appClient.ReceiveTimeout = 5000;
                appStream = stream;
                TargetId = Guid.NewGuid().ToString();
                IsBound = false;
                HasAppLimits = false;
            }

            SendEnvelope("bind", TargetId, "", "targetId");
            while (!stopping && client.Connected)
            {
                string text = ReadTextFrame(stream);
                if (text == null) break;
                if (text.Length > 0) HandleMessage(text);
            }
        }
        catch (Exception ex)
        {
            if (!stopping) LastError = ex.Message;
        }
        finally
        {
            lock (sync)
            {
                if (ReferenceEquals(appClient, client))
                {
                    appClient = null;
                    appStream = null;
                    TargetId = "";
                    IsBound = false;
                    HasAppLimits = false;
                }
            }
            try { client.Close(); } catch { }
        }
    }

    private void HandleMessage(string text)
    {
        Dictionary<string, object> message = json.Deserialize<Dictionary<string, object>>(text);
        object typeValue, clientValue, targetValue, bodyValue;
        message.TryGetValue("type", out typeValue);
        message.TryGetValue("clientId", out clientValue);
        message.TryGetValue("targetId", out targetValue);
        message.TryGetValue("message", out bodyValue);
        string type = Convert.ToString(typeValue);
        string clientId = Convert.ToString(clientValue);
        string targetId = Convert.ToString(targetValue);
        string body = Convert.ToString(bodyValue);
        if (type == "bind" && body == "DGLAB" && clientId == ClientId && targetId == TargetId)
        {
            IsBound = true;
            SendEnvelope("bind", ClientId, TargetId, "200");
        }
        else if (type == "msg" && IsBound && clientId == TargetId && targetId == ClientId)
        {
            Match strength = Regex.Match(body ?? "", @"^strength-(\d{1,3})\+(\d{1,3})\+(\d{1,3})\+(\d{1,3})$", RegexOptions.IgnoreCase);
            if (strength.Success)
            {
                int a = Math.Min(200, Int32.Parse(strength.Groups[1].Value));
                int b = Math.Min(200, Int32.Parse(strength.Groups[2].Value));
                int limitA = Math.Min(200, Int32.Parse(strength.Groups[3].Value));
                int limitB = Math.Min(200, Int32.Parse(strength.Groups[4].Value));
                lock (sync)
                {
                    AppStrengthA = a;
                    AppStrengthB = b;
                    AppLimitA = limitA;
                    AppLimitB = limitB;
                    HasAppLimits = true;
                    StrengthUpdateCount++;
                }
            }
        }
    }

    public void SendCommand(string command)
    {
        if (!IsBound || string.IsNullOrEmpty(TargetId)) throw new InvalidOperationException("DG-Lab App is not bound.");
        SendEnvelope("msg", ClientId, TargetId, command);
    }

    public bool StopOutputReliable(int attempts)
    {
        string[] commands = new[] { "strength-1+2+0", "strength-2+2+0", "clear-1", "clear-2" };
        bool[] sent = new bool[commands.Length];
        int rounds = Math.Max(1, attempts);
        for (int round = 0; round < rounds; round++)
        {
            for (int i = 0; i < commands.Length; i++)
            {
                if (sent[i]) continue;
                try { SendCommand(commands[i]); sent[i] = true; }
                catch (Exception ex) { LastError = ex.Message; }
            }
            if (Array.TrueForAll(sent, value => value)) return true;
            Thread.Sleep(50);
        }
        return Array.TrueForAll(sent, value => value);
    }

    public void ArmSafetyTimeout(int milliseconds)
    {
        int due = Math.Max(100, milliseconds);
        lock (sync)
        {
            if (safetyTimer == null) safetyTimer = new Timer(SafetyTimeoutElapsed, null, Timeout.Infinite, Timeout.Infinite);
            safetyTimer.Change(due, Timeout.Infinite);
        }
    }

    public void CancelSafetyTimeout()
    {
        lock (sync) { if (safetyTimer != null) safetyTimer.Change(Timeout.Infinite, Timeout.Infinite); }
    }

    private void SafetyTimeoutElapsed(object state)
    {
        bool stopped = StopOutputReliable(3);
        LastWatchdogStopSucceeded = stopped;
        Interlocked.Increment(ref watchdogStopCount);
    }

    private int watchdogStopCount;

    private void SendEnvelope(string type, string clientId, string targetId, string message)
    {
        string payload = json.Serialize(new Dictionary<string, object>
        {
            { "type", type }, { "clientId", clientId }, { "targetId", targetId }, { "message", message }
        });
        lock (sync)
        {
            if (appStream == null) throw new IOException("DG-Lab App WebSocket is not connected.");
            WriteTextFrame(appStream, payload);
        }
    }

    private static string ReadHttpRequest(NetworkStream stream)
    {
        MemoryStream buffer = new MemoryStream();
        int matched = 0;
        byte[] marker = new byte[] { 13, 10, 13, 10 };
        while (buffer.Length < 16384)
        {
            int value = stream.ReadByte();
            if (value < 0) throw new EndOfStreamException();
            buffer.WriteByte((byte)value);
            matched = value == marker[matched] ? matched + 1 : (value == marker[0] ? 1 : 0);
            if (matched == marker.Length) break;
        }
        return Encoding.ASCII.GetString(buffer.ToArray());
    }

    private static string GetHeader(string request, string name)
    {
        string[] lines = request.Split(new[] { "\r\n" }, StringSplitOptions.None);
        foreach (string line in lines)
        {
            int colon = line.IndexOf(':');
            if (colon > 0 && string.Equals(line.Substring(0, colon).Trim(), name, StringComparison.OrdinalIgnoreCase))
                return line.Substring(colon + 1).Trim();
        }
        return null;
    }

    private static string ReadTextFrame(NetworkStream stream)
    {
        int first = stream.ReadByte();
        if (first < 0) return null;
        int second = stream.ReadByte();
        if (second < 0) return null;
        int opcode = first & 0x0F;
        bool masked = (second & 0x80) != 0;
        if (!masked) throw new InvalidDataException("Client WebSocket frames must be masked.");
        ulong length = (ulong)(second & 0x7F);
        if (length == 126) length = (ulong)((stream.ReadByte() << 8) | stream.ReadByte());
        else if (length == 127)
        {
            length = 0;
            for (int i = 0; i < 8; i++) length = (length << 8) | (byte)stream.ReadByte();
        }
        if (length > 65536) throw new InvalidDataException("WebSocket frame is too large.");
        byte[] mask = masked ? ReadExact(stream, 4) : null;
        byte[] payload = ReadExact(stream, (int)length);
        if (masked)
            for (int i = 0; i < payload.Length; i++) payload[i] = (byte)(payload[i] ^ mask[i % 4]);
        if (opcode == 8) return null;
        if (opcode == 9) { WriteFrame(stream, 10, payload); return ""; }
        if (opcode != 1) return "";
        return Encoding.UTF8.GetString(payload);
    }

    private static byte[] ReadExact(Stream stream, int count)
    {
        byte[] bytes = new byte[count];
        int offset = 0;
        while (offset < count)
        {
            int read = stream.Read(bytes, offset, count - offset);
            if (read <= 0) throw new EndOfStreamException();
            offset += read;
        }
        return bytes;
    }

    private static void WriteTextFrame(Stream stream, string text) { WriteFrame(stream, 1, Encoding.UTF8.GetBytes(text)); }

    private static void WriteFrame(Stream stream, int opcode, byte[] payload)
    {
        MemoryStream frame = new MemoryStream();
        frame.WriteByte((byte)(0x80 | opcode));
        if (payload.Length < 126) frame.WriteByte((byte)payload.Length);
        else
        {
            frame.WriteByte(126);
            frame.WriteByte((byte)((payload.Length >> 8) & 0xFF));
            frame.WriteByte((byte)(payload.Length & 0xFF));
        }
        frame.Write(payload, 0, payload.Length);
        byte[] bytes = frame.ToArray();
        stream.Write(bytes, 0, bytes.Length);
        stream.Flush();
    }

    public void Stop()
    {
        stopping = true;
        IsRunning = false;
        IsBound = false;
        try { if (listener != null) listener.Stop(); } catch { }
        lock (sync)
        {
            if (safetyTimer != null) { safetyTimer.Dispose(); safetyTimer = null; }
            try { if (appClient != null) appClient.Close(); } catch { }
            appClient = null;
            appStream = null;
        }
    }

    public void Dispose() { Stop(); }
}

public sealed class DglabRemoteSocketTransport : IDisposable
{
    private readonly object sync = new object();
    private readonly ClientWebSocket socket;
    private readonly JavaScriptSerializer json = new JavaScriptSerializer();
    private Timer safetyTimer;
    private int watchdogStopCount;
    private string clientId = "";
    private string targetId = "";

    public string LastError { get; private set; }
    public int WatchdogStopCount { get { return watchdogStopCount; } }
    public bool LastWatchdogStopSucceeded { get; private set; }

    public DglabRemoteSocketTransport(ClientWebSocket socket)
    {
        if (socket == null) throw new ArgumentNullException("socket");
        this.socket = socket;
        LastError = "";
        LastWatchdogStopSucceeded = true;
    }

    public void UpdateBinding(string clientId, string targetId)
    {
        lock (sync)
        {
            this.clientId = clientId ?? "";
            this.targetId = targetId ?? "";
        }
    }

    public void SendCommand(string command)
    {
        lock (sync)
        {
            if (socket.State != WebSocketState.Open) throw new InvalidOperationException("Socket is not open.");
            if (string.IsNullOrEmpty(clientId) || string.IsNullOrEmpty(targetId)) throw new InvalidOperationException("DG-Lab App is not bound.");
            string payload = json.Serialize(new Dictionary<string, object>
            {
                { "type", "msg" }, { "clientId", clientId }, { "targetId", targetId }, { "message", command }
            });
            byte[] bytes = Encoding.UTF8.GetBytes(payload);
            using (CancellationTokenSource timeout = new CancellationTokenSource(1000))
            {
                socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, timeout.Token).GetAwaiter().GetResult();
            }
        }
    }

    public bool StopOutputReliable(int attempts)
    {
        string[] commands = new[] { "strength-1+2+0", "strength-2+2+0", "clear-1", "clear-2" };
        bool[] sent = new bool[commands.Length];
        int rounds = Math.Max(1, attempts);
        for (int round = 0; round < rounds; round++)
        {
            for (int i = 0; i < commands.Length; i++)
            {
                if (sent[i]) continue;
                try { SendCommand(commands[i]); sent[i] = true; }
                catch (Exception ex) { LastError = ex.Message; }
            }
            if (Array.TrueForAll(sent, value => value)) return true;
            Thread.Sleep(50);
        }
        return Array.TrueForAll(sent, value => value);
    }

    public void ArmSafetyTimeout(int milliseconds)
    {
        int due = Math.Max(100, milliseconds);
        lock (sync)
        {
            if (safetyTimer == null) safetyTimer = new Timer(SafetyTimeoutElapsed, null, Timeout.Infinite, Timeout.Infinite);
            safetyTimer.Change(due, Timeout.Infinite);
        }
    }

    public void CancelSafetyTimeout()
    {
        lock (sync) { if (safetyTimer != null) safetyTimer.Change(Timeout.Infinite, Timeout.Infinite); }
    }

    private void SafetyTimeoutElapsed(object state)
    {
        bool stopped = StopOutputReliable(3);
        LastWatchdogStopSucceeded = stopped;
        Interlocked.Increment(ref watchdogStopCount);
    }

    public void Dispose()
    {
        lock (sync)
        {
            if (safetyTimer != null) { safetyTimer.Dispose(); safetyTimer = null; }
        }
    }
}
"@

$xaml = @"
<Window
  xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
  xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
  Title="OC 设定写作督促工具"
  Width="1280"
  Height="820"
  MinWidth="1080"
  MinHeight="700"
  WindowStartupLocation="CenterScreen"
  Background="#181818">
  <Window.Resources>
    <SolidColorBrush x:Key="Ink" Color="#E8E8E8"/>
    <SolidColorBrush x:Key="Muted" Color="#A0A0A0"/>
    <SolidColorBrush x:Key="Panel" Color="#262626"/>
    <SolidColorBrush x:Key="Line" Color="#3A3A3A"/>
    <SolidColorBrush x:Key="Primary" Color="#2D8CFF"/>
    <SolidColorBrush x:Key="PrimaryDark" Color="#66B3FF"/>
    <SolidColorBrush x:Key="PrimarySoft" Color="#25384A"/>
    <SolidColorBrush x:Key="Danger" Color="#D83B3B"/>
    <SolidColorBrush x:Key="DangerDark" Color="#A52A2A"/>
    <SolidColorBrush x:Key="Soft" Color="#303030"/>

    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="FontFamily" Value="Microsoft YaHei UI"/>
    </Style>

    <Style TargetType="Button">
      <Setter Property="FontFamily" Value="Microsoft YaHei UI"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="Normal"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="MinHeight" Value="32"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border
              Background="{TemplateBinding Background}"
              BorderBrush="{TemplateBinding BorderBrush}"
              BorderThickness="{TemplateBinding BorderThickness}"
              CornerRadius="3">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="PrimaryButton" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Background" Value="{StaticResource Primary}"/>
    </Style>

    <Style x:Key="SecondaryButton" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="Background" Value="{StaticResource Soft}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>

    <Style x:Key="DangerButton" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Background" Value="{StaticResource Danger}"/>
    </Style>

    <Style x:Key="NavButton" TargetType="Button">
      <Setter Property="Foreground" Value="#E8E8E8"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Padding" Value="12,8"/>
      <Setter Property="MinHeight" Value="36"/>
    </Style>

    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{StaticResource Panel}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="3"/>
      <Setter Property="Padding" Value="12"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="FontFamily" Value="Microsoft YaHei UI"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="8,5"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Background" Value="#1F1F1F"/>
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
    </Style>

    <Style TargetType="ComboBox">
      <Setter Property="FontFamily" Value="Microsoft YaHei UI"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="6,4"/>
      <Setter Property="MinHeight" Value="32"/>
      <Setter Property="Background" Value="#181818"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="BorderBrush" Value="#5A5A5A"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid x:Name="ComboRoot" SnapsToDevicePixels="True">
              <Border
                x:Name="ComboBorder"
                Background="#181818"
                BorderBrush="#5A5A5A"
                BorderThickness="1"
                CornerRadius="3"/>
              <ContentPresenter
                x:Name="SelectedContent"
                Margin="10,0,38,0"
                HorizontalAlignment="Left"
                VerticalAlignment="Center"
                Content="{TemplateBinding SelectionBoxItem}"
                ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"
                TextElement.Foreground="#FFFFFF"
                TextElement.FontWeight="SemiBold"
                IsHitTestVisible="False"/>
              <ToggleButton
                x:Name="DropDownToggle"
                Width="34"
                HorizontalAlignment="Right"
                Background="Transparent"
                BorderThickness="0"
                Focusable="False"
                ClickMode="Press"
                IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border Background="Transparent">
                      <Path
                        Width="10"
                        Height="6"
                        HorizontalAlignment="Center"
                        VerticalAlignment="Center"
                        Data="M 0 0 L 5 5 L 10 0 Z"
                        Fill="#FFFFFF"/>
                    </Border>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <Popup
                x:Name="PART_Popup"
                AllowsTransparency="True"
                Focusable="False"
                IsOpen="{TemplateBinding IsDropDownOpen}"
                Placement="Bottom"
                PopupAnimation="Fade">
                <Border
                  MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
                  MaxHeight="320"
                  Background="#252525"
                  BorderBrush="#5A5A5A"
                  BorderThickness="1"
                  CornerRadius="3">
                  <ScrollViewer CanContentScroll="True" VerticalScrollBarVisibility="Auto">
                    <ItemsPresenter/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocusWithin" Value="True">
                <Setter TargetName="ComboBorder" Property="BorderBrush" Value="#2D8CFF"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="ComboRoot" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ComboBoxItem">
      <Setter Property="FontFamily" Value="Microsoft YaHei UI"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Background" Value="#252525"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="MinHeight" Value="32"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="ItemBorder" Background="{TemplateBinding Background}" Padding="10,6">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter Property="Background" Value="#2D8CFF"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter Property="Background" Value="#1F6FBE"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Foreground" Value="#777777"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ListBox">
      <Setter Property="FontFamily" Value="Microsoft YaHei UI"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="Background" Value="#1F1F1F"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="220"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <Border Grid.Column="0" Background="#202020" BorderBrush="#3A3A3A" BorderThickness="0,0,1,0">
      <DockPanel Margin="14">
        <StackPanel DockPanel.Dock="Top">
          <StackPanel Orientation="Horizontal" Margin="0,0,0,22">
            <Border Width="40" Height="40" CornerRadius="3" Background="#2D8CFF">
              <TextBlock Text="OC" Foreground="White" FontSize="16" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <StackPanel Margin="10,1,0,0">
              <TextBlock Text="写作督促" Foreground="White" FontSize="18" FontWeight="Bold"/>
              <TextBlock Text="功能导航" Foreground="#A0A0A0" FontSize="11"/>
            </StackPanel>
          </StackPanel>
          <Button x:Name="NavDashboardButton" Style="{StaticResource NavButton}" Content="控制台" Margin="0,0,0,6"/>
          <Button x:Name="NavScopeButton" Style="{StaticResource NavButton}" Content="范围规则" Margin="0,0,0,6"/>
          <Button x:Name="NavTriggerButton" Style="{StaticResource NavButton}" Content="触发设置" Margin="0,0,0,6"/>
          <Button x:Name="NavDeviceButton" Style="{StaticResource NavButton}" Content="设备与安全" Margin="0,0,0,6"/>
          <Button x:Name="NavLogsButton" Style="{StaticResource NavButton}" Content="日志" Margin="0,0,0,6"/>
        </StackPanel>
        <Border DockPanel.Dock="Bottom" Background="#2B2B2B" BorderBrush="#3A3A3A" BorderThickness="1" CornerRadius="3" Padding="10">
          <StackPanel>
            <TextBlock Text="Windows 全局检测" Foreground="White" FontWeight="Bold" FontSize="12"/>
            <TextBlock Text="窗口与键鼠活动仅在本机处理。" Foreground="#A0A0A0" TextWrapping="Wrap" Margin="0,4,0,0" FontSize="11"/>
          </StackPanel>
        </Border>
      </DockPanel>
    </Border>

      <ScrollViewer x:Name="MainScrollViewer" Grid.Column="1" Background="#1F1F1F" VerticalScrollBarVisibility="Auto">
      <Grid Margin="12">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Grid Grid.Row="0" Margin="0,0,0,10" Height="42">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel>
            <TextBlock x:Name="PageEyebrowValue" Text="FOCUS SESSION  /  DASHBOARD" Foreground="{StaticResource Muted}" FontSize="10" FontWeight="Bold"/>
            <TextBlock x:Name="PageTitleValue" Text="控制台" FontSize="22" FontWeight="Bold" Margin="0,2,0,0"/>
          </StackPanel>
          <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
             <Border Background="#303030" BorderBrush="#5A5A5A" BorderThickness="1" CornerRadius="3" Padding="10,4" Margin="0,0,8,0">
               <StackPanel>
                 <TextBlock x:Name="ActualStrengthValue" Text="A --  |  B --" Foreground="White" FontWeight="Bold" FontSize="13" HorizontalAlignment="Center"/>
                 <TextBlock x:Name="ActualStrengthSource" Text="未连接" Foreground="{StaticResource Muted}" FontSize="9" HorizontalAlignment="Center"/>
               </StackPanel>
             </Border>
             <Border Background="#25384A" CornerRadius="3" Padding="10,5" Margin="0,0,8,0">
              <TextBlock x:Name="DeviceBadge" Text="HTTP 桥接" Foreground="#66B3FF" FontWeight="Bold"/>
            </Border>
             <Border x:Name="LockBadgeBorder" Background="#25384A" CornerRadius="3" Padding="10,5" Margin="0,0,8,0">
               <TextBlock x:Name="LockBadge" Text="未锁定" Foreground="#66B3FF" FontWeight="Bold"/>
             </Border>
            <Button x:Name="FloatingMonitorButton" Style="{StaticResource SecondaryButton}" Content="悬浮监控" Width="94" Height="34" Margin="0,0,8,0"/>
            <Button x:Name="EmergencyButton" Style="{StaticResource DangerButton}" Content="急停" Width="86" Height="34" FontWeight="Bold"/>
          </StackPanel>
        </Grid>

        <Grid x:Name="DashboardPage" Grid.Row="1">
           <Border Style="{StaticResource Card}" Margin="0,0,0,8" MinHeight="300">
            <StackPanel>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                  <TextBlock Text="当前专注窗口" FontSize="20" FontWeight="Bold"/>
                  <TextBlock Text="实时读取 Windows 前台窗口，并立即与范围规则匹配。" Foreground="{StaticResource Muted}" Margin="0,4,0,0"/>
                </StackPanel>
                <Border Grid.Column="1" Background="#25384A" BorderBrush="#2D8CFF" BorderThickness="1" CornerRadius="3" Padding="10,5" VerticalAlignment="Center">
                  <TextBlock Text="实时检测中" Foreground="#66B3FF" FontWeight="Bold"/>
                </Border>
              </Grid>
              <Border Background="#181818" BorderBrush="#5A5A5A" BorderThickness="1" CornerRadius="3" Padding="14" Margin="0,18,0,0">
                <StackPanel>
                  <TextBlock Text="程序名 | 窗口标题" Foreground="{StaticResource Muted}" FontSize="11"/>
                  <TextBox x:Name="CurrentWindowInput" Text="等待检测..." IsReadOnly="True" FontSize="16" FontWeight="SemiBold" Margin="0,6,0,0"/>
                </StackPanel>
              </Border>
              <UniformGrid Columns="3" Margin="0,14,0,0">
                <Border Background="#303030" CornerRadius="3" Padding="14" Margin="0,0,8,0">
                  <StackPanel>
                    <TextBlock Text="范围判定" Foreground="{StaticResource Muted}" FontSize="11"/>
                    <TextBlock x:Name="CurrentWindowMatchValue" Text="未匹配" FontSize="18" FontWeight="Bold" Margin="0,4,0,0"/>
                  </StackPanel>
                </Border>
                <Border Background="#303030" CornerRadius="3" Padding="14" Margin="0,0,8,0">
                  <StackPanel>
                    <TextBlock Text="检测来源" Foreground="{StaticResource Muted}" FontSize="11"/>
                    <TextBlock Text="Windows 前台窗口" FontSize="16" FontWeight="Bold" Margin="0,4,0,0"/>
                  </StackPanel>
                </Border>
                <Border Background="#303030" CornerRadius="3" Padding="14">
                  <StackPanel>
                    <TextBlock Text="刷新周期" Foreground="{StaticResource Muted}" FontSize="11"/>
                    <TextBlock Text="每 1 秒" FontSize="18" FontWeight="Bold" Margin="0,4,0,0"/>
                  </StackPanel>
                </Border>
              </UniformGrid>
              <TextBlock Text="判定顺序：黑名单优先，其次白名单；未命中任何规则时按离开页面处理。窗口规则请在“范围规则”页面维护。" Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,14,0,0"/>
            </StackPanel>
          </Border>
        </Grid>

        <Grid x:Name="SettingsPage" Grid.Row="2">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="0.9*"/>
            <ColumnDefinition Width="1.35*"/>
          </Grid.ColumnDefinitions>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <Border x:Name="SessionControlPanel" Grid.ColumnSpan="2" Style="{StaticResource Card}" Margin="0,0,0,8">
            <StackPanel>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                  <TextBlock Text="当前状态" Foreground="{StaticResource Muted}" FontSize="12" FontWeight="Bold"/>
                  <TextBlock x:Name="StatusValue" Text="未开始" FontSize="30" FontWeight="Bold" Margin="0,4,0,0"/>
                </StackPanel>
                <TextBlock x:Name="SessionValue" Grid.Column="1" Text="45:00" FontSize="44" FontWeight="Bold" Foreground="{StaticResource PrimaryDark}" VerticalAlignment="Center"/>
              </Grid>
              <UniformGrid Columns="3" Margin="0,16,0,0">
                <Border Background="#303030" CornerRadius="3" Padding="12" Margin="0,0,8,0">
                  <StackPanel>
                    <TextBlock Text="离开计时" Foreground="{StaticResource Muted}" FontSize="12"/>
                    <TextBlock x:Name="LeftValue" Text="00:00" FontSize="21" FontWeight="Bold" Margin="0,4,0,0"/>
                  </StackPanel>
                </Border>
                <Border Background="#303030" CornerRadius="3" Padding="12" Margin="0,0,8,0">
                  <StackPanel>
                    <TextBlock Text="分心计时" Foreground="{StaticResource Muted}" FontSize="12"/>
                    <TextBlock x:Name="DistractionValue" Text="00:00" FontSize="21" FontWeight="Bold" Margin="0,4,0,0"/>
                  </StackPanel>
                </Border>
                <Border Background="#303030" CornerRadius="3" Padding="12">
                  <StackPanel>
                    <TextBlock Text="全局无输入" Foreground="{StaticResource Muted}" FontSize="12"/>
                    <TextBlock x:Name="IdleValue" Text="00:00" FontSize="21" FontWeight="Bold" Margin="0,4,0,0"/>
                  </StackPanel>
                </Border>
              </UniformGrid>
              <WrapPanel Margin="0,16,0,0">
                <Button x:Name="StartButton" Style="{StaticResource PrimaryButton}" Content="开始专注" Width="110" Margin="0,0,8,0"/>
                <Button x:Name="PauseButton" Style="{StaticResource SecondaryButton}" Content="暂停/恢复" Width="110" Margin="0,0,8,0"/>
                <Button x:Name="EndButton" Style="{StaticResource SecondaryButton}" Content="结束" Width="82" Margin="0,0,8,0"/>
                <Button x:Name="UnlockButton" Style="{StaticResource SecondaryButton}" Content="解除锁定" Width="110" IsEnabled="False" Margin="0,0,8,0"/>
                <Button x:Name="ManualTestButton" Style="{StaticResource PrimaryButton}" Content="测试触发" Width="100"/>
              </WrapPanel>
            </StackPanel>
          </Border>

          <Border x:Name="TriggerStrategyPanel" Grid.Row="1" Style="{StaticResource Card}" Margin="0,0,8,8">
            <StackPanel>
              <TextBlock Text="触发策略" FontSize="18" FontWeight="Bold"/>
              <TextBlock Text="检测事件只负责发出惩罚请求；本区域决定何时触发、是否持续及重复触发方式。" Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,4,0,14"/>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <StackPanel Margin="0,0,8,10">
                  <TextBlock Text="专注时长（分钟）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="FocusMinutesInput" Text="45"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Margin="0,0,0,10">
                  <TextBlock Text="离开触发（秒）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="LeaveInput" Text="300"/>
                </StackPanel>
                <StackPanel Grid.Row="1" Margin="0,0,8,10">
                  <TextBlock Text="Windows 全局无输入（秒）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="IdleInput" Text="600"/>
                </StackPanel>
                <StackPanel Grid.Row="1" Grid.Column="1" Margin="0,0,0,10">
                  <TextBlock Text="输出结束方式" Foreground="{StaticResource Muted}"/>
                  <ComboBox x:Name="OutputModeCombo" SelectedIndex="0">
                    <ComboBoxItem Content="返回白名单时停止"/>
                    <ComboBoxItem Content="固定时长后停止"/>
                  </ComboBox>
                </StackPanel>
                <StackPanel Grid.Row="2" Margin="0,0,8,0">
                  <TextBlock Text="重复触发处理" Foreground="{StaticResource Muted}"/>
                  <ComboBox x:Name="OverlapModeCombo" SelectedIndex="0">
                    <ComboBoxItem Content="重新计时"/>
                    <ComboBoxItem Content="叠加时长"/>
                  </ComboBox>
                </StackPanel>
                <StackPanel Grid.Row="2" Grid.Column="1">
                  <TextBlock Text="黑名单策略" Foreground="{StaticResource Muted}"/>
                  <TextBox Text="命中立即触发" IsReadOnly="True"/>
                </StackPanel>
                <StackPanel Grid.Row="3" Margin="0,10,8,0">
                  <TextBlock Text="持续模式最长输出（秒，1–30）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="MaxContinuousInput" Text="10"/>
                </StackPanel>
                <StackPanel Grid.Row="3" Grid.Column="1" Margin="0,10,0,0">
                  <TextBlock Text="持续模式冷却时间（秒，5–3600）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="HoldCooldownInput" Text="60"/>
                </StackPanel>
              </Grid>
            </StackPanel>
          </Border>

          <Border x:Name="CoyoteOutputPanel" Grid.Row="1" Grid.Column="1" Style="{StaticResource Card}" Margin="0,0,0,8">
            <StackPanel>
              <TextBlock Text="郊狼输出配置" FontSize="18" FontWeight="Bold"/>
              <TextBlock Text="V3 原始强度为 0–200；波形按每 100ms 四个 25ms 数据点发送。" Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,4,0,14"/>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <StackPanel Margin="0,0,8,10">
                  <TextBlock Text="输出通道" Foreground="{StaticResource Muted}"/>
                  <ComboBox x:Name="ChannelModeCombo" SelectedIndex="0">
                    <ComboBoxItem Content="A + B 双通道"/>
                    <ComboBoxItem Content="仅 A 通道"/>
                    <ComboBoxItem Content="仅 B 通道"/>
                  </ComboBox>
                </StackPanel>
                <StackPanel Grid.Column="1" Margin="0,0,8,10">
                  <TextBlock Text="A 强度范围（0–200）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="StrengthARangeInput" Text="40-60"/>
                </StackPanel>
                <StackPanel Grid.Column="2" Margin="0,0,0,10">
                  <TextBlock Text="B 强度范围（0–200）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="StrengthBRangeInput" Text="40-60"/>
                </StackPanel>
                <StackPanel Grid.Row="1" Margin="0,0,8,10">
                  <TextBlock Text="波形预设" Foreground="{StaticResource Muted}"/>
                  <ComboBox x:Name="WaveformCombo" SelectedIndex="0">
                    <ComboBoxItem Content="恒定"/>
                    <ComboBoxItem Content="间歇"/>
                    <ComboBoxItem Content="渐强"/>
                    <ComboBoxItem Content="心跳"/>
                  </ComboBox>
                </StackPanel>
                <StackPanel Grid.Row="1" Grid.Column="1" Margin="0,0,8,10">
                  <TextBlock Text="波形周期 ms（10–1000）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="WavePeriodInput" Text="30"/>
                </StackPanel>
                <StackPanel Grid.Row="1" Grid.Column="2" Margin="0,0,0,10">
                  <TextBlock Text="波形强度（0–100）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="WaveIntensityInput" Text="35"/>
                </StackPanel>
                <StackPanel Grid.Row="2" Margin="0,0,8,0">
                  <TextBlock Text="固定持续时间（秒，1–30）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="DurationInput" Text="5"/>
                </StackPanel>
                <Border Grid.Row="2" Grid.Column="1" Grid.ColumnSpan="2" Background="#303030" CornerRadius="3" Padding="10">
                  <TextBlock Text="安全说明：通道强度受下方 BF 软上限二次限制；急停会立即将 A/B 强度归零。" Foreground="{StaticResource Muted}" TextWrapping="Wrap"/>
                </Border>
              </Grid>
            </StackPanel>
          </Border>

          <Border x:Name="DeviceSafetyPanel" Grid.Row="2" Grid.ColumnSpan="2" Style="{StaticResource Card}" Margin="0,0,0,8">
            <StackPanel>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                  <TextBlock Text="设备连接与强度安全上限" FontSize="18" FontWeight="Bold"/>
                  <TextBlock Text="Socket 使用 App 上报上限；蓝牙和 HTTP 使用本页手动上限。蓝牙 BF 参数会在每次重连后重新写入。" Foreground="{StaticResource Muted}" Margin="0,4,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal">
                  <Border Background="#303030" CornerRadius="3" Padding="12,8">
                    <StackPanel>
                      <TextBlock Text="设备状态" Foreground="{StaticResource Muted}" FontSize="11"/>
                      <TextBlock x:Name="DeviceValue" Text="未连接" FontWeight="Bold"/>
                    </StackPanel>
                  </Border>
                </StackPanel>
              </Grid>
              <StackPanel Margin="0,14,0,12">
                <TextBlock Text="连接模式" Foreground="{StaticResource Muted}"/>
                <ComboBox x:Name="DeviceModeCombo" SelectedIndex="0" Width="230" HorizontalAlignment="Left">
                  <ComboBoxItem Content="HTTP 真实设备桥接"/>
                  <ComboBoxItem Content="蓝牙 V3 直连"/>
                  <ComboBoxItem Content="Socket 控制协议"/>
                </ComboBox>

                <Border x:Name="HttpConnectionPage" Background="#252525" CornerRadius="4" Padding="12" Margin="0,10,0,0">
                  <StackPanel>
                    <TextBlock Text="HTTP 真实设备桥接" FontWeight="Bold"/>
                    <TextBlock Text="桥接服务地址" Foreground="{StaticResource Muted}" Margin="0,8,0,0"/>
                    <TextBox x:Name="HttpEndpointInput" Text="http://127.0.0.1:8080"/>
                    <TextBlock Text="远程地址必须使用 HTTPS；HTTP 仅允许回环或私有/链路本地 IP。连接时会访问 /status。" Foreground="{StaticResource Muted}" FontSize="11" TextWrapping="Wrap" Margin="0,4,0,0"/>
                    <Grid Margin="0,8,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                      <StackPanel Margin="0,0,8,0"><TextBlock Text="A 手动上限（0–200）" Foreground="{StaticResource Muted}"/><TextBox x:Name="HttpLimitAInput" Text="80"/></StackPanel>
                      <StackPanel Grid.Column="1"><TextBlock Text="B 手动上限（0–200）" Foreground="{StaticResource Muted}"/><TextBox x:Name="HttpLimitBInput" Text="80"/></StackPanel>
                    </Grid>
                  </StackPanel>
                </Border>

                <Border x:Name="BleConnectionPage" Background="#252525" CornerRadius="4" Padding="12" Margin="0,10,0,0" Visibility="Collapsed">
                  <StackPanel>
                    <TextBlock Text="蓝牙 V3 直连" FontWeight="Bold"/>
                    <TextBlock Text="12 位蓝牙地址" Foreground="{StaticResource Muted}" Margin="0,8,0,0"/>
                    <TextBox x:Name="BleAddressInput" Text=""/>
                    <TextBlock Text="在 Windows 设置 → 蓝牙和设备 → 设备中打开设备详情，查看“蓝牙地址”；填写 12 位十六进制字符，例如 001A7DDA7113。" Foreground="{StaticResource Muted}" FontSize="11" TextWrapping="Wrap" Margin="0,4,0,8"/>
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                      </Grid.ColumnDefinitions>
                      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                      <StackPanel Margin="0,0,8,8"><TextBlock Text="A 软上限（0–200）" Foreground="{StaticResource Muted}"/><TextBox x:Name="SoftLimitAInput" Text="80"/></StackPanel>
                      <StackPanel Grid.Column="1" Margin="0,0,8,8"><TextBlock Text="B 软上限（0–200）" Foreground="{StaticResource Muted}"/><TextBox x:Name="SoftLimitBInput" Text="80"/></StackPanel>
                      <StackPanel Grid.Column="2" Margin="0,0,8,8"><TextBlock Text="A 频率平衡（0–255）" Foreground="{StaticResource Muted}"/><TextBox x:Name="FrequencyBalanceAInput" Text="0"/></StackPanel>
                      <StackPanel Grid.Column="3" Margin="0,0,0,8"><TextBlock Text="B 频率平衡（0–255）" Foreground="{StaticResource Muted}"/><TextBox x:Name="FrequencyBalanceBInput" Text="0"/></StackPanel>
                      <StackPanel Grid.Row="1" Margin="0,0,8,0"><TextBlock Text="A 脉宽平衡（0–255）" Foreground="{StaticResource Muted}"/><TextBox x:Name="StrengthBalanceAInput" Text="0"/></StackPanel>
                      <StackPanel Grid.Row="1" Grid.Column="1" Margin="0,0,8,0"><TextBlock Text="B 脉宽平衡（0–255）" Foreground="{StaticResource Muted}"/><TextBox x:Name="StrengthBalanceBInput" Text="0"/></StackPanel>
                    </Grid>
                  </StackPanel>
                </Border>

                <Border x:Name="SocketConnectionPage" Background="#252525" CornerRadius="4" Padding="12" Margin="0,10,0,0" Visibility="Collapsed">
                  <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="220"/></Grid.ColumnDefinitions>
                    <StackPanel Margin="0,0,16,0">
                      <TextBlock Text="DG-Lab Socket 控制协议" FontWeight="Bold"/>
                      <TextBlock Text="服务器方式" Foreground="{StaticResource Muted}" Margin="0,8,0,0"/>
                      <ComboBox x:Name="SocketServerModeCombo" SelectedIndex="0">
                        <ComboBoxItem Content="在本机建立 Socket 服务器"/>
                        <ComboBoxItem Content="连接外部 Socket 服务器"/>
                      </ComboBox>
                      <Grid x:Name="LocalSocketSettings" Margin="0,8,0,8">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="2*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                        <StackPanel Margin="0,0,8,0">
                          <TextBlock Text="手机访问本机的 IP / 域名" Foreground="{StaticResource Muted}"/>
                          <TextBox x:Name="LocalSocketHostInput"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1">
                          <TextBlock Text="监听端口" Foreground="{StaticResource Muted}"/>
                          <TextBox x:Name="LocalSocketPortInput" Text="5678"/>
                        </StackPanel>
                      </Grid>
                      <StackPanel x:Name="RemoteSocketSettings" Margin="0,8,0,8" Visibility="Collapsed">
                        <TextBlock Text="外部 WebSocket 服务器地址" Foreground="{StaticResource Muted}"/>
                        <TextBox x:Name="SocketServerInput" Text="ws://192.168.1.100:5678"/>
                        <TextBlock Text="远程服务器必须使用 WSS；WS 仅允许回环或私有/链路本地 IP。" Foreground="{StaticResource Muted}" FontSize="11" TextWrapping="Wrap" Margin="0,4,0,0"/>
                      </StackPanel>
                      <TextBlock Text="本地模式仅监听所填的回环或私有/链路本地 IP；请在 Windows 防火墙中仅对专用网络放行。启动后，用 DG-Lab App 扫描右侧二维码或手动填写生成的地址。" Foreground="{StaticResource Muted}" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8"/>
                      <TextBlock Text="绑定状态" Foreground="{StaticResource Muted}"/>
                      <TextBlock x:Name="SocketBindStatusText" Text="未连接服务器" FontWeight="Bold" Margin="0,2,0,8"/>
                      <TextBlock Text="App 当前强度 / 上限" Foreground="{StaticResource Muted}"/>
                      <TextBlock x:Name="SocketAppLimitsText" Text="等待 App 上报 A/B 强度上限；未上报前禁止输出" FontWeight="Bold" TextWrapping="Wrap" Margin="0,2,0,8"/>
                      <TextBlock Text="App 手动连接地址" Foreground="{StaticResource Muted}"/>
                      <TextBox x:Name="SocketManualAddressText" IsReadOnly="True" Margin="0,2,0,8"/>
                      <TextBlock Text="二维码内容（可复制）" Foreground="{StaticResource Muted}"/>
                      <TextBox x:Name="SocketQrContentText" IsReadOnly="True" TextWrapping="Wrap" MinHeight="44" VerticalScrollBarVisibility="Auto"/>
                    </StackPanel>
                    <Border Grid.Column="1" Background="White" Width="200" Height="200" HorizontalAlignment="Center" VerticalAlignment="Top">
                      <Grid>
                        <Image x:Name="SocketQrImage" Stretch="Uniform" Margin="8"/>
                        <TextBlock x:Name="SocketQrPlaceholder" Text="连接服务器后生成二维码" Foreground="#666666" TextWrapping="Wrap" TextAlignment="Center" VerticalAlignment="Center" Margin="20"/>
                      </Grid>
                    </Border>
                  </Grid>
                </Border>
              </StackPanel>
              <WrapPanel>
                <Button x:Name="ConnectButton" Style="{StaticResource PrimaryButton}" Content="连接 HTTP 桥接" Width="190" Margin="0,0,8,0"/>
                <Button x:Name="ApplySafetyButton" Style="{StaticResource SecondaryButton}" Content="重新应用 BF 参数" Width="145" Margin="0,0,8,0" Visibility="Collapsed"/>
                <Button x:Name="DisconnectButton" Style="{StaticResource SecondaryButton}" Content="断开" Width="78" Margin="0,0,8,0"/>
                <Button x:Name="StopButton" Style="{StaticResource DangerButton}" Content="立即停止 A/B" Width="125"/>
              </WrapPanel>
            </StackPanel>
          </Border>
        </Grid>

         <Border x:Name="LowerPages" Grid.Row="3" Style="{StaticResource Card}" Margin="0">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="1.1*"/>
              <ColumnDefinition Width="1.4*"/>
            </Grid.ColumnDefinitions>
            <StackPanel x:Name="ScopeRulesPanel" Margin="0,0,18,0">
              <TextBlock Text="范围规则" FontSize="18" FontWeight="Bold"/>
              <Border Background="#303030" CornerRadius="3" Padding="12" Margin="0,14,0,0">
                <StackPanel>
                  <TextBlock Text="窗口选择器" FontWeight="Bold"/>
                  <TextBlock Text="从当前可见窗口中选择目标，再加入白名单或黑名单。" Foreground="{StaticResource Muted}" Margin="0,4,0,8"/>
                  <ComboBox x:Name="WindowPickerCombo"/>
                  <Button x:Name="RefreshWindowListButton" Style="{StaticResource SecondaryButton}" Content="刷新窗口列表" Margin="0,8,0,0"/>
                </StackPanel>
              </Border>
              <Border Background="#303030" CornerRadius="3" Padding="12" Margin="0,14,0,0">
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel Margin="0,0,8,0">
                    <TextBlock Text="窗口白名单" FontSize="16" FontWeight="Bold"/>
                    <TextBlock Text="命中后视为正常写作窗口，不执行离开惩罚。" Foreground="{StaticResource Muted}" Margin="0,4,0,0" TextWrapping="Wrap"/>
                    <WrapPanel Margin="0,10,0,8">
                      <Button x:Name="AddWhitelistButton" Style="{StaticResource SecondaryButton}" Content="添加白名单" Width="104" Margin="0,0,8,0"/>
                      <Button x:Name="RemoveWhitelistButton" Style="{StaticResource SecondaryButton}" Content="删除选中" Width="92"/>
                    </WrapPanel>
                    <ListBox x:Name="WhitelistList" Height="150"/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Margin="8,0,0,0">
                    <TextBlock Text="窗口黑名单" FontSize="16" FontWeight="Bold"/>
                    <TextBlock Text="命中后立即触发，并持续到返回白名单。" Foreground="{StaticResource Muted}" Margin="0,4,0,0" TextWrapping="Wrap"/>
                    <WrapPanel Margin="0,10,0,8">
                      <Button x:Name="AddBlacklistButton" Style="{StaticResource SecondaryButton}" Content="添加黑名单" Width="104" Margin="0,0,8,0"/>
                      <Button x:Name="RemoveBlacklistButton" Style="{StaticResource SecondaryButton}" Content="删除选中" Width="92"/>
                    </WrapPanel>
                    <ListBox x:Name="BlacklistList" Height="150"/>
                  </StackPanel>
                </Grid>
              </Border>
            </StackPanel>

            <StackPanel x:Name="LogsPanel" Grid.Column="1">
              <Border Background="#303030" CornerRadius="3" Padding="12" Margin="0,0,0,14">
                <StackPanel>
                  <TextBlock Text="配置管理" FontSize="16" FontWeight="Bold"/>
                  <TextBlock Text="导入会先停止当前输出并断开 Socket；配置文件使用版本化 JSON 格式。" Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,4,0,10"/>
                  <WrapPanel>
                    <Button x:Name="ImportConfigButton" Style="{StaticResource SecondaryButton}" Content="导入配置" Width="96" Margin="0,0,8,0"/>
                    <Button x:Name="ExportConfigButton" Style="{StaticResource SecondaryButton}" Content="导出配置" Width="96" Margin="0,0,8,0"/>
                    <Button x:Name="ResetSafeConfigButton" Style="{StaticResource DangerButton}" Content="恢复安全默认值" Width="130"/>
                  </WrapPanel>
                </StackPanel>
              </Border>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Text="最近日志" FontSize="18" FontWeight="Bold"/>
                <Button x:Name="ClearLogsButton" Grid.Column="1" Style="{StaticResource SecondaryButton}" Content="清空" Width="72"/>
              </Grid>
              <ListBox x:Name="LogList" MinHeight="420" Margin="0,14,0,0" BorderBrush="{StaticResource Line}" Background="#1F1F1F"/>
            </StackPanel>
          </Grid>
        </Border>
      </Grid>
    </ScrollViewer>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

function Find-Control($Name) {
  return $window.FindName($Name)
}

$MainScrollViewer = Find-Control "MainScrollViewer"
$PageEyebrowValue = Find-Control "PageEyebrowValue"
$PageTitleValue = Find-Control "PageTitleValue"
$NavDashboardButton = Find-Control "NavDashboardButton"
$NavScopeButton = Find-Control "NavScopeButton"
$NavTriggerButton = Find-Control "NavTriggerButton"
$NavDeviceButton = Find-Control "NavDeviceButton"
$NavLogsButton = Find-Control "NavLogsButton"
$DashboardPage = Find-Control "DashboardPage"
$SettingsPage = Find-Control "SettingsPage"
$SessionControlPanel = Find-Control "SessionControlPanel"
$TriggerStrategyPanel = Find-Control "TriggerStrategyPanel"
$CoyoteOutputPanel = Find-Control "CoyoteOutputPanel"
$DeviceSafetyPanel = Find-Control "DeviceSafetyPanel"
$LowerPages = Find-Control "LowerPages"
$ScopeRulesPanel = Find-Control "ScopeRulesPanel"
$LogsPanel = Find-Control "LogsPanel"

$StatusValue = Find-Control "StatusValue"
$SessionValue = Find-Control "SessionValue"
$LeftValue = Find-Control "LeftValue"
$DistractionValue = Find-Control "DistractionValue"
$IdleValue = Find-Control "IdleValue"
$DeviceValue = Find-Control "DeviceValue"
$DeviceBadge = Find-Control "DeviceBadge"
$ActualStrengthValue = Find-Control "ActualStrengthValue"
$ActualStrengthSource = Find-Control "ActualStrengthSource"
$LockBadge = Find-Control "LockBadge"
$LockBadgeBorder = Find-Control "LockBadgeBorder"
$DeviceModeCombo = Find-Control "DeviceModeCombo"
$HttpConnectionPage = Find-Control "HttpConnectionPage"
$BleConnectionPage = Find-Control "BleConnectionPage"
$SocketConnectionPage = Find-Control "SocketConnectionPage"
$HttpEndpointInput = Find-Control "HttpEndpointInput"
$HttpLimitAInput = Find-Control "HttpLimitAInput"
$HttpLimitBInput = Find-Control "HttpLimitBInput"
$BleAddressInput = Find-Control "BleAddressInput"
$SocketServerModeCombo = Find-Control "SocketServerModeCombo"
$LocalSocketSettings = Find-Control "LocalSocketSettings"
$RemoteSocketSettings = Find-Control "RemoteSocketSettings"
$LocalSocketHostInput = Find-Control "LocalSocketHostInput"
$LocalSocketPortInput = Find-Control "LocalSocketPortInput"
$SocketServerInput = Find-Control "SocketServerInput"
$SocketBindStatusText = Find-Control "SocketBindStatusText"
$SocketAppLimitsText = Find-Control "SocketAppLimitsText"
$SocketManualAddressText = Find-Control "SocketManualAddressText"
$SocketQrContentText = Find-Control "SocketQrContentText"
$SocketQrImage = Find-Control "SocketQrImage"
$SocketQrPlaceholder = Find-Control "SocketQrPlaceholder"
$CurrentWindowInput = Find-Control "CurrentWindowInput"
$CurrentWindowMatchValue = Find-Control "CurrentWindowMatchValue"
$WindowPickerCombo = Find-Control "WindowPickerCombo"
$RefreshWindowListButton = Find-Control "RefreshWindowListButton"
$WhitelistList = Find-Control "WhitelistList"
$BlacklistList = Find-Control "BlacklistList"
$AddWhitelistButton = Find-Control "AddWhitelistButton"
$RemoveWhitelistButton = Find-Control "RemoveWhitelistButton"
$AddBlacklistButton = Find-Control "AddBlacklistButton"
$RemoveBlacklistButton = Find-Control "RemoveBlacklistButton"
$FocusMinutesInput = Find-Control "FocusMinutesInput"
$LeaveInput = Find-Control "LeaveInput"
$IdleInput = Find-Control "IdleInput"
$OutputModeCombo = Find-Control "OutputModeCombo"
$OverlapModeCombo = Find-Control "OverlapModeCombo"
$ChannelModeCombo = Find-Control "ChannelModeCombo"
$StrengthARangeInput = Find-Control "StrengthARangeInput"
$StrengthBRangeInput = Find-Control "StrengthBRangeInput"
$WaveformCombo = Find-Control "WaveformCombo"
$WavePeriodInput = Find-Control "WavePeriodInput"
$WaveIntensityInput = Find-Control "WaveIntensityInput"
$DurationInput = Find-Control "DurationInput"
$MaxContinuousInput = Find-Control "MaxContinuousInput"
$HoldCooldownInput = Find-Control "HoldCooldownInput"
$SoftLimitAInput = Find-Control "SoftLimitAInput"
$SoftLimitBInput = Find-Control "SoftLimitBInput"
$FrequencyBalanceAInput = Find-Control "FrequencyBalanceAInput"
$FrequencyBalanceBInput = Find-Control "FrequencyBalanceBInput"
$StrengthBalanceAInput = Find-Control "StrengthBalanceAInput"
$StrengthBalanceBInput = Find-Control "StrengthBalanceBInput"
$LogList = Find-Control "LogList"

$StartButton = Find-Control "StartButton"
$PauseButton = Find-Control "PauseButton"
$EndButton = Find-Control "EndButton"
$UnlockButton = Find-Control "UnlockButton"
$EmergencyButton = Find-Control "EmergencyButton"
$ManualTestButton = Find-Control "ManualTestButton"
$FloatingMonitorButton = Find-Control "FloatingMonitorButton"
$ConnectButton = Find-Control "ConnectButton"
$ApplySafetyButton = Find-Control "ApplySafetyButton"
$DisconnectButton = Find-Control "DisconnectButton"
$StopButton = Find-Control "StopButton"
$ClearLogsButton = Find-Control "ClearLogsButton"
$ImportConfigButton = Find-Control "ImportConfigButton"
$ExportConfigButton = Find-Control "ExportConfigButton"
$ResetSafeConfigButton = Find-Control "ResetSafeConfigButton"

$script:State = @{
  Running = $false
  Paused = $false
  Locked = $false
  Connected = $false
  DeviceMode = "http"
  WindowState = "writing"
  LastWindowKey = ""
  AwayEpisodeActive = $false
  EpisodeTriggerSent = $false
  SessionSeconds = 45 * 60
  LeftSeconds = 0
  DistractionSeconds = 0
  IdleSeconds = 0
  IdleTriggerSent = $false
  FocusStartedAt = [DateTime]::MinValue
  OutputActive = $false
  OutputHoldUntilWhitelist = $false
  OutputProfile = $null
  OutputEnd = [DateTime]::MinValue
  ActualStrengthKnown = $false
  ActualStrengthA = 0
  ActualStrengthB = 0
  ActualStrengthSource = "未连接"
  HoldRetriggerPending = $false
  HoldCooldownEnd = [DateTime]::MinValue
  HttpRenewAt = [DateTime]::MinValue
  SocketClient = $null
  SocketTransport = $null
  SocketClientId = ""
  SocketTargetId = ""
  SocketServerUri = ""
  SocketReceiveTask = $null
  SocketReceiveBuffer = $null
  LocalSocketServer = $null
  LocalSocketLastError = ""
  SocketWatchdogStopCount = 0
  SocketAppStrengthA = 0
  SocketAppStrengthB = 0
  SocketAppLimitA = 0
  SocketAppLimitB = 0
  SocketHasAppLimits = $false
  SocketStrengthUpdateCount = 0
  SocketServerMode = "local"
}

$script:FloatingMonitorWindow = $null
$script:FloatingStrengthAValue = $null
$script:FloatingStrengthBValue = $null
$script:FloatingDurationValue = $null
$script:FloatingRemainingValue = $null
$script:FloatingSourceValue = $null

function Get-IntText($TextBox, [int]$Default) {
  $value = 0
  if ([int]::TryParse($TextBox.Text, [ref]$value)) { return $value }
  return $Default
}

function Format-Seconds([int]$Seconds) {
  if ($Seconds -lt 0) { $Seconds = 0 }
  return "{0:00}:{1:00}" -f [Math]::Floor($Seconds / 60), ($Seconds % 60)
}

function Get-CurrentOutputDurationSeconds {
  if ($script:State.OutputActive -and $null -ne $script:State.OutputProfile) {
    $milliseconds = if ($script:State.OutputHoldUntilWhitelist) {
      [int]$script:State.OutputProfile.MaxContinuousMs
    } else {
      [int]$script:State.OutputProfile.DurationMs
    }
    return [Math]::Max(1, [int][Math]::Ceiling($milliseconds / 1000.0))
  }
  return (Get-ClampedInt $DurationInput 5 1 30)
}

function Update-FloatingMonitor {
  if ($null -eq $script:FloatingMonitorWindow) { return }
  if ($script:State.ActualStrengthKnown) {
    $script:FloatingStrengthAValue.Text = [string]$script:State.ActualStrengthA
    $script:FloatingStrengthBValue.Text = [string]$script:State.ActualStrengthB
  } else {
    $script:FloatingStrengthAValue.Text = "--"
    $script:FloatingStrengthBValue.Text = "--"
  }
  $durationSeconds = Get-CurrentOutputDurationSeconds
  $script:FloatingDurationValue.Text = "本次持续：$durationSeconds 秒"
  if ($script:State.OutputActive) {
    $remaining = [Math]::Max(0, ($script:State.OutputEnd - (Get-Date)).TotalSeconds)
    $script:FloatingRemainingValue.Text = ("剩余时间：{0:0.0} 秒" -f $remaining)
  } else {
    $script:FloatingRemainingValue.Text = "剩余时间：未输出"
  }
  $script:FloatingSourceValue.Text = $script:State.ActualStrengthSource
}

function New-FloatingMonitorWindow {
  $floatingXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="A/B 强度监控" Width="330" Height="190" MinWidth="330" MinHeight="190"
        WindowStyle="ToolWindow" ResizeMode="NoResize" ShowInTaskbar="False" Topmost="True"
        WindowStartupLocation="CenterOwner" Background="#202020">
  <Border Background="#202020" BorderBrush="#2D8CFF" BorderThickness="1" CornerRadius="4" Padding="14">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <TextBlock Text="A/B 通道实时监控" Foreground="#E8E8E8" FontFamily="Microsoft YaHei UI" FontSize="15" FontWeight="Bold"/>
      <Grid Grid.Row="1" Margin="0,10,0,8">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border Background="#303030" CornerRadius="3" Padding="12" Margin="0,0,6,0">
          <StackPanel><TextBlock Text="通道 A" Foreground="#A0A0A0" FontFamily="Microsoft YaHei UI"/><TextBlock x:Name="FloatingStrengthAValue" Text="--" Foreground="#66B3FF" FontFamily="Microsoft YaHei UI" FontSize="28" FontWeight="Bold" HorizontalAlignment="Center"/></StackPanel>
        </Border>
        <Border Grid.Column="1" Background="#303030" CornerRadius="3" Padding="12" Margin="6,0,0,0">
          <StackPanel><TextBlock Text="通道 B" Foreground="#A0A0A0" FontFamily="Microsoft YaHei UI"/><TextBlock x:Name="FloatingStrengthBValue" Text="--" Foreground="#66B3FF" FontFamily="Microsoft YaHei UI" FontSize="28" FontWeight="Bold" HorizontalAlignment="Center"/></StackPanel>
        </Border>
      </Grid>
      <Grid Grid.Row="2">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <TextBlock x:Name="FloatingDurationValue" Text="本次持续：5 秒" Foreground="#E8E8E8" FontFamily="Microsoft YaHei UI" FontWeight="Bold"/>
        <TextBlock x:Name="FloatingRemainingValue" Grid.Column="1" Text="剩余时间：未输出" Foreground="#E8E8E8" FontFamily="Microsoft YaHei UI" FontWeight="Bold" HorizontalAlignment="Right"/>
      </Grid>
      <TextBlock x:Name="FloatingSourceValue" Grid.Row="3" Text="未连接" Foreground="#A0A0A0" FontFamily="Microsoft YaHei UI" FontSize="10" TextTrimming="CharacterEllipsis" Margin="0,7,0,0"/>
    </Grid>
  </Border>
</Window>
"@
  $reader = New-Object Xml.XmlNodeReader ([xml]$floatingXaml)
  $floatingWindow = [Windows.Markup.XamlReader]::Load($reader)
  if ($window.IsVisible) { $floatingWindow.Owner = $window }
  $script:FloatingStrengthAValue = $floatingWindow.FindName("FloatingStrengthAValue")
  $script:FloatingStrengthBValue = $floatingWindow.FindName("FloatingStrengthBValue")
  $script:FloatingDurationValue = $floatingWindow.FindName("FloatingDurationValue")
  $script:FloatingRemainingValue = $floatingWindow.FindName("FloatingRemainingValue")
  $script:FloatingSourceValue = $floatingWindow.FindName("FloatingSourceValue")
  $floatingWindow.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    if ($eventArgs.ButtonState -eq [Windows.Input.MouseButtonState]::Pressed) {
      try { $sender.DragMove() } catch {}
    }
  })
  $floatingWindow.Add_Closed({
    $script:FloatingMonitorWindow = $null
    $script:FloatingStrengthAValue = $null
    $script:FloatingStrengthBValue = $null
    $script:FloatingDurationValue = $null
    $script:FloatingRemainingValue = $null
    $script:FloatingSourceValue = $null
    $FloatingMonitorButton.Content = "悬浮监控"
  })
  return $floatingWindow
}

function Toggle-FloatingMonitor {
  if ($null -ne $script:FloatingMonitorWindow) {
    $script:FloatingMonitorWindow.Close()
    return
  }
  $script:FloatingMonitorWindow = New-FloatingMonitorWindow
  Update-FloatingMonitor
  $FloatingMonitorButton.Content = "关闭悬浮"
  $script:FloatingMonitorWindow.Show()
}

function Get-SystemIdleSeconds {
  try {
    return [int][Math]::Floor([NativeWindowApi]::GetIdleMilliseconds() / 1000)
  } catch {
    return 0
  }
}

function Add-Log($Message) {
  $time = Get-Date -Format "HH:mm:ss"
  $LogList.Items.Insert(0, "[$time] $Message")
  while ($LogList.Items.Count -gt 80) {
    $LogList.Items.RemoveAt($LogList.Items.Count - 1)
  }
}

function Set-ActualStrengthState([int]$StrengthA, [int]$StrengthB, [string]$Source, [bool]$Known = $true) {
  $script:State.ActualStrengthKnown = $Known
  $script:State.ActualStrengthA = [Math]::Max(0, [Math]::Min(200, $StrengthA))
  $script:State.ActualStrengthB = [Math]::Max(0, [Math]::Min(200, $StrengthB))
  $script:State.ActualStrengthSource = if ([string]::IsNullOrWhiteSpace($Source)) { "未知来源" } else { $Source }
  if ($Known) {
    $ActualStrengthValue.Text = "A $($script:State.ActualStrengthA)  |  B $($script:State.ActualStrengthB)"
  } else {
    $ActualStrengthValue.Text = "A --  |  B --"
  }
  $ActualStrengthSource.Text = $script:State.ActualStrengthSource
  Update-FloatingMonitor
}

function Get-RequiredConfigValue($Object, [string]$Name) {
  if ($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Name) {
    throw "配置缺少字段：$Name"
  }
  return $Object.$Name
}

function ConvertTo-ConfigInt($Value, [string]$Name, [int]$Minimum, [int]$Maximum) {
  $parsed = 0
  if (-not [int]::TryParse([string]$Value, [ref]$parsed)) {
    throw "配置字段 $Name 必须是整数。"
  }
  if ($parsed -lt $Minimum -or $parsed -gt $Maximum) {
    throw "配置字段 $Name 必须在 $Minimum 至 $Maximum 之间。"
  }
  return $parsed
}

function ConvertTo-ConfigText($Value, [string]$Name, [int]$MaximumLength, [switch]$AllowEmpty) {
  $text = [string]$Value
  if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($text)) {
    throw "配置字段 $Name 不能为空。"
  }
  if ($text.Length -gt $MaximumLength) {
    throw "配置字段 $Name 超过最大长度 $MaximumLength。"
  }
  return $text.Trim()
}

function ConvertTo-ConfigChoice($Value, [string]$Name, [string[]]$Choices) {
  $text = [string]$Value
  if ($text -notin $Choices) {
    throw "配置字段 $Name 的值无效：$text"
  }
  return $text
}

function Test-TrustedPlaintextHost([Uri]$Uri) {
  if ($Uri.IsLoopback) { return $true }
  $address = $null
  if (-not [Net.IPAddress]::TryParse($Uri.DnsSafeHost, [ref]$address)) { return $false }
  $bytes = $address.GetAddressBytes()
  if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
    return $bytes[0] -eq 10 -or
      ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
      ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or
      ($bytes[0] -eq 169 -and $bytes[1] -eq 254)
  }
  if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) {
    return [Net.IPAddress]::IsLoopback($address) -or
      (($bytes[0] -band 0xFE) -eq 0xFC) -or
      ($bytes[0] -eq 0xFE -and ($bytes[1] -band 0xC0) -eq 0x80)
  }
  return $false
}

function Assert-SecureNetworkEndpoint([string]$Text, [ValidateSet("http", "socket")][string]$Kind) {
  $label = if ($Kind -eq "http") { "HTTP 桥接地址" } else { "WebSocket 服务器地址" }
  if ([string]::IsNullOrWhiteSpace($Text)) { throw "$label 不能为空。" }
  $uri = $null
  if (-not [Uri]::TryCreate($Text.Trim(), [UriKind]::Absolute, [ref]$uri) -or [string]::IsNullOrWhiteSpace($uri.Host)) {
    throw "$label 不是有效的绝对 URL。"
  }
  if (-not [string]::IsNullOrEmpty($uri.UserInfo)) { throw "$label 不允许在 URL 中携带用户名或密码。" }
  if (-not [string]::IsNullOrEmpty($uri.Fragment) -or -not [string]::IsNullOrEmpty($uri.Query)) {
    throw "$label 不允许包含查询参数或片段。"
  }
  $secureScheme = if ($Kind -eq "http") { "https" } else { "wss" }
  $plainScheme = if ($Kind -eq "http") { "http" } else { "ws" }
  if ($uri.Scheme -eq $secureScheme) { return $uri }
  if ($uri.Scheme -ne $plainScheme) {
    throw "$label 必须使用 $secureScheme`://；可信本机或局域网可使用 $plainScheme`://。"
  }
  if (-not (Test-TrustedPlaintextHost $uri)) {
    throw "$plainScheme`:// 明文连接仅允许回环、RFC1918 私有或链路本地 IP；远程地址必须使用 $secureScheme`://。"
  }
  return $uri
}

function Get-DesktopConfiguration {
  $rangeA = Get-NumericRange $StrengthARangeInput 40 60 200
  $rangeB = Get-NumericRange $StrengthBRangeInput 40 60 200
  return [ordered]@{
    schemaVersion = 2
    focus = [ordered]@{
      sessionMinutes = Get-ClampedInt $FocusMinutesInput 45 1 10080
      leaveSeconds = Get-ClampedInt $LeaveInput 300 1 86400
      idleSeconds = Get-ClampedInt $IdleInput 600 1 86400
    }
    trigger = [ordered]@{
      outputMode = @("untilWhitelist", "fixedDuration")[[Math]::Max(0, [Math]::Min(1, $OutputModeCombo.SelectedIndex))]
      overlapMode = @("restart", "extend")[[Math]::Max(0, [Math]::Min(1, $OverlapModeCombo.SelectedIndex))]
      channel = @("both", "A", "B")[[Math]::Max(0, [Math]::Min(2, $ChannelModeCombo.SelectedIndex))]
      strengthA = @($rangeA[0], $rangeA[1])
      strengthB = @($rangeB[0], $rangeB[1])
      waveform = @("constant", "pulse", "ramp", "heartbeat")[[Math]::Max(0, [Math]::Min(3, $WaveformCombo.SelectedIndex))]
      wavePeriodMs = Get-ClampedInt $WavePeriodInput 30 10 1000
      waveIntensity = Get-ClampedInt $WaveIntensityInput 35 0 100
      durationSeconds = Get-ClampedInt $DurationInput 5 1 30
      maxContinuousSeconds = Get-ClampedInt $MaxContinuousInput 10 1 30
      cooldownSeconds = Get-ClampedInt $HoldCooldownInput 60 5 3600
    }
    device = [ordered]@{
      mode = @("http", "ble", "socket")[[Math]::Max(0, [Math]::Min(2, $DeviceModeCombo.SelectedIndex))]
      httpEndpoint = $HttpEndpointInput.Text.Trim()
      bleAddress = $BleAddressInput.Text.Trim()
      socket = [ordered]@{
        mode = @("local", "remote")[[Math]::Max(0, [Math]::Min(1, $SocketServerModeCombo.SelectedIndex))]
        localHost = $LocalSocketHostInput.Text.Trim()
        localPort = Get-ClampedInt $LocalSocketPortInput 5678 1 65535
        remoteServer = $SocketServerInput.Text.Trim()
      }
    }
    safety = [ordered]@{
      httpLimitA = Get-ClampedInt $HttpLimitAInput 80 0 200
      httpLimitB = Get-ClampedInt $HttpLimitBInput 80 0 200
      softLimitA = Get-ClampedInt $SoftLimitAInput 80 0 200
      softLimitB = Get-ClampedInt $SoftLimitBInput 80 0 200
      frequencyBalanceA = Get-ClampedInt $FrequencyBalanceAInput 0 0 255
      frequencyBalanceB = Get-ClampedInt $FrequencyBalanceBInput 0 0 255
      strengthBalanceA = Get-ClampedInt $StrengthBalanceAInput 0 0 255
      strengthBalanceB = Get-ClampedInt $StrengthBalanceBInput 0 0 255
    }
    scope = [ordered]@{
      whitelist = @($WhitelistList.Items | ForEach-Object { [string]$_ })
      blacklist = @($BlacklistList.Items | ForEach-Object { [string]$_ })
    }
  }
}

function Get-SafeDesktopConfiguration {
  return [pscustomobject]@{
    schemaVersion = 2
    focus = [pscustomobject]@{ sessionMinutes = 45; leaveSeconds = 300; idleSeconds = 600 }
    trigger = [pscustomobject]@{
      outputMode = "fixedDuration"; overlapMode = "restart"; channel = "both"
      strengthA = @(10, 20); strengthB = @(10, 20); waveform = "constant"
      wavePeriodMs = 30; waveIntensity = 20; durationSeconds = 1
      maxContinuousSeconds = 10; cooldownSeconds = 60
    }
    device = [pscustomobject]@{
      mode = "http"; httpEndpoint = "http://127.0.0.1:8080"; bleAddress = ""
      socket = [pscustomobject]@{ mode = "local"; localHost = (Get-PreferredLocalIpv4Address); localPort = 5678; remoteServer = "ws://192.168.1.100:5678" }
    }
    safety = [pscustomobject]@{
      httpLimitA = 30; httpLimitB = 30; softLimitA = 30; softLimitB = 30; frequencyBalanceA = 0; frequencyBalanceB = 0
      strengthBalanceA = 0; strengthBalanceB = 0
    }
    scope = [pscustomobject]@{ whitelist = @(); blacklist = @() }
  }
}

function Stop-ForConfigurationChange {
  if ($script:State.OutputActive -or $script:Ble.OutputActive) {
    Invoke-DeviceStop | Out-Null
  }
  if ($null -ne $script:State.SocketClient -or $null -ne $script:State.LocalSocketServer) {
    Reset-SocketConnection
  }
  $script:State.Connected = $false
}

function Set-DesktopConfiguration($Config, [string]$SourceName) {
  $version = ConvertTo-ConfigInt (Get-RequiredConfigValue $Config "schemaVersion") "schemaVersion" 1 2
  $focus = Get-RequiredConfigValue $Config "focus"
  $trigger = Get-RequiredConfigValue $Config "trigger"
  $device = Get-RequiredConfigValue $Config "device"
  $socket = Get-RequiredConfigValue $device "socket"
  $safety = Get-RequiredConfigValue $Config "safety"
  $scope = Get-RequiredConfigValue $Config "scope"

  $sessionMinutes = ConvertTo-ConfigInt (Get-RequiredConfigValue $focus "sessionMinutes") "focus.sessionMinutes" 1 10080
  $leaveSeconds = ConvertTo-ConfigInt (Get-RequiredConfigValue $focus "leaveSeconds") "focus.leaveSeconds" 1 86400
  $idleSeconds = ConvertTo-ConfigInt (Get-RequiredConfigValue $focus "idleSeconds") "focus.idleSeconds" 1 86400
  $outputMode = ConvertTo-ConfigChoice (Get-RequiredConfigValue $trigger "outputMode") "trigger.outputMode" @("untilWhitelist", "fixedDuration")
  $overlapMode = ConvertTo-ConfigChoice (Get-RequiredConfigValue $trigger "overlapMode") "trigger.overlapMode" @("restart", "extend")
  $channel = ConvertTo-ConfigChoice (Get-RequiredConfigValue $trigger "channel") "trigger.channel" @("both", "A", "B")
  $waveform = ConvertTo-ConfigChoice (Get-RequiredConfigValue $trigger "waveform") "trigger.waveform" @("constant", "pulse", "ramp", "heartbeat")
  $strengthA = @(Get-RequiredConfigValue $trigger "strengthA")
  $strengthB = @(Get-RequiredConfigValue $trigger "strengthB")
  if ($strengthA.Count -ne 2 -or $strengthB.Count -ne 2) { throw "强度范围必须包含最小值和最大值。" }
  $strengthAMin = ConvertTo-ConfigInt $strengthA[0] "trigger.strengthA[0]" 0 200
  $strengthAMax = ConvertTo-ConfigInt $strengthA[1] "trigger.strengthA[1]" $strengthAMin 200
  $strengthBMin = ConvertTo-ConfigInt $strengthB[0] "trigger.strengthB[0]" 0 200
  $strengthBMax = ConvertTo-ConfigInt $strengthB[1] "trigger.strengthB[1]" $strengthBMin 200
  $wavePeriod = ConvertTo-ConfigInt (Get-RequiredConfigValue $trigger "wavePeriodMs") "trigger.wavePeriodMs" 10 1000
  $waveIntensity = ConvertTo-ConfigInt (Get-RequiredConfigValue $trigger "waveIntensity") "trigger.waveIntensity" 0 100
  if ($version -eq 1 -and $trigger.PSObject.Properties.Name -notcontains "durationSeconds") {
    $legacyDurationMs = ConvertTo-ConfigInt (Get-RequiredConfigValue $trigger "durationMs") "trigger.durationMs" 100 30000
    $durationSeconds = [Math]::Max(1, [Math]::Min(30, [int][Math]::Ceiling($legacyDurationMs / 1000.0)))
  } else {
    $durationSeconds = ConvertTo-ConfigInt (Get-RequiredConfigValue $trigger "durationSeconds") "trigger.durationSeconds" 1 30
  }
  $maxContinuousSeconds = if ($trigger.PSObject.Properties.Name -contains "maxContinuousSeconds") {
    ConvertTo-ConfigInt $trigger.maxContinuousSeconds "trigger.maxContinuousSeconds" 1 30
  } else { 10 }
  $cooldownSeconds = if ($trigger.PSObject.Properties.Name -contains "cooldownSeconds") {
    ConvertTo-ConfigInt $trigger.cooldownSeconds "trigger.cooldownSeconds" 5 3600
  } else { 60 }
  $deviceMode = ConvertTo-ConfigChoice (Get-RequiredConfigValue $device "mode") "device.mode" @("http", "ble", "socket")
  $httpEndpoint = ConvertTo-ConfigText (Get-RequiredConfigValue $device "httpEndpoint") "device.httpEndpoint" 2048
  $bleAddress = ConvertTo-ConfigText (Get-RequiredConfigValue $device "bleAddress") "device.bleAddress" 64 -AllowEmpty
  $socketMode = ConvertTo-ConfigChoice (Get-RequiredConfigValue $socket "mode") "device.socket.mode" @("local", "remote")
  $localHost = ConvertTo-ConfigText (Get-RequiredConfigValue $socket "localHost") "device.socket.localHost" 255
  $localPort = ConvertTo-ConfigInt (Get-RequiredConfigValue $socket "localPort") "device.socket.localPort" 1 65535
  $remoteServer = ConvertTo-ConfigText (Get-RequiredConfigValue $socket "remoteServer") "device.socket.remoteServer" 2048
  [void](Assert-SecureNetworkEndpoint $httpEndpoint "http")
  [void](Assert-SecureNetworkEndpoint $remoteServer "socket")
  [void](Assert-SecureNetworkEndpoint "ws://$localHost`:$localPort" "socket")
  $softLimitA = ConvertTo-ConfigInt (Get-RequiredConfigValue $safety "softLimitA") "safety.softLimitA" 0 200
  $softLimitB = ConvertTo-ConfigInt (Get-RequiredConfigValue $safety "softLimitB") "safety.softLimitB" 0 200
  $httpLimitA = if ($safety.PSObject.Properties.Name -contains "httpLimitA") { ConvertTo-ConfigInt $safety.httpLimitA "safety.httpLimitA" 0 200 } else { $softLimitA }
  $httpLimitB = if ($safety.PSObject.Properties.Name -contains "httpLimitB") { ConvertTo-ConfigInt $safety.httpLimitB "safety.httpLimitB" 0 200 } else { $softLimitB }
  $frequencyBalanceA = ConvertTo-ConfigInt (Get-RequiredConfigValue $safety "frequencyBalanceA") "safety.frequencyBalanceA" 0 255
  $frequencyBalanceB = ConvertTo-ConfigInt (Get-RequiredConfigValue $safety "frequencyBalanceB") "safety.frequencyBalanceB" 0 255
  $strengthBalanceA = ConvertTo-ConfigInt (Get-RequiredConfigValue $safety "strengthBalanceA") "safety.strengthBalanceA" 0 255
  $strengthBalanceB = ConvertTo-ConfigInt (Get-RequiredConfigValue $safety "strengthBalanceB") "safety.strengthBalanceB" 0 255
  $whitelist = @(Get-RequiredConfigValue $scope "whitelist")
  $blacklist = @(Get-RequiredConfigValue $scope "blacklist")
  if ($whitelist.Count -gt 500 -or $blacklist.Count -gt 500) { throw "黑白名单分别最多允许 500 项。" }
  $validatedWhitelist = @($whitelist | ForEach-Object { ConvertTo-ConfigText $_ "scope.whitelist" 512 })
  $validatedBlacklist = @($blacklist | ForEach-Object { ConvertTo-ConfigText $_ "scope.blacklist" 512 })

  Stop-ForConfigurationChange
  $FocusMinutesInput.Text = [string]$sessionMinutes
  $LeaveInput.Text = [string]$leaveSeconds
  $IdleInput.Text = [string]$idleSeconds
  $OutputModeCombo.SelectedIndex = @("untilWhitelist", "fixedDuration").IndexOf($outputMode)
  $OverlapModeCombo.SelectedIndex = @("restart", "extend").IndexOf($overlapMode)
  $ChannelModeCombo.SelectedIndex = @("both", "A", "B").IndexOf($channel)
  $StrengthARangeInput.Text = "$strengthAMin-$strengthAMax"
  $StrengthBRangeInput.Text = "$strengthBMin-$strengthBMax"
  $WaveformCombo.SelectedIndex = @("constant", "pulse", "ramp", "heartbeat").IndexOf($waveform)
  $WavePeriodInput.Text = [string]$wavePeriod
  $WaveIntensityInput.Text = [string]$waveIntensity
  $DurationInput.Text = [string]$durationSeconds
  $MaxContinuousInput.Text = [string]$maxContinuousSeconds
  $HoldCooldownInput.Text = [string]$cooldownSeconds
  $HttpEndpointInput.Text = $httpEndpoint
  $BleAddressInput.Text = $bleAddress
  $LocalSocketHostInput.Text = $localHost
  $LocalSocketPortInput.Text = [string]$localPort
  $SocketServerInput.Text = $remoteServer
  $HttpLimitAInput.Text = [string]$httpLimitA
  $HttpLimitBInput.Text = [string]$httpLimitB
  $SoftLimitAInput.Text = [string]$softLimitA
  $SoftLimitBInput.Text = [string]$softLimitB
  $FrequencyBalanceAInput.Text = [string]$frequencyBalanceA
  $FrequencyBalanceBInput.Text = [string]$frequencyBalanceB
  $StrengthBalanceAInput.Text = [string]$strengthBalanceA
  $StrengthBalanceBInput.Text = [string]$strengthBalanceB
  $WhitelistList.Items.Clear()
  foreach ($item in $validatedWhitelist) { [void]$WhitelistList.Items.Add($item) }
  $BlacklistList.Items.Clear()
  foreach ($item in $validatedBlacklist) { [void]$BlacklistList.Items.Add($item) }
  $SocketServerModeCombo.SelectedIndex = @("local", "remote").IndexOf($socketMode)
  $DeviceModeCombo.SelectedIndex = @("http", "ble", "socket").IndexOf($deviceMode)
  Refresh-CurrentWindow | Out-Null
  Add-Log "已应用配置：$SourceName（格式版本 $version）"
  Update-View
}

function Export-DesktopConfiguration {
  $dialog = New-Object Microsoft.Win32.SaveFileDialog
  $dialog.Title = "导出写作督促配置"
  $dialog.Filter = "JSON 配置文件 (*.json)|*.json"
  $dialog.FileName = "OCWritingFocus.config.json"
  $dialog.AddExtension = $true
  if ($dialog.ShowDialog() -ne $true) { return }
  $json = (Get-DesktopConfiguration) | ConvertTo-Json -Depth 8
  [IO.File]::WriteAllText($dialog.FileName, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($true)))
  Add-Log "配置已导出：$($dialog.FileName)"
}

function Import-DesktopConfiguration {
  $dialog = New-Object Microsoft.Win32.OpenFileDialog
  $dialog.Title = "导入写作督促配置"
  $dialog.Filter = "JSON 配置文件 (*.json)|*.json"
  $dialog.CheckFileExists = $true
  if ($dialog.ShowDialog() -ne $true) { return }
  try {
    $file = Get-Item -LiteralPath $dialog.FileName
    if ($file.Length -gt 1048576) { throw "配置文件不能超过 1 MB。" }
    $config = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    Set-DesktopConfiguration $config $file.Name
  } catch {
    Add-Log "配置导入失败：$($_.Exception.Message)"
    [Windows.MessageBox]::Show("配置导入失败：`r`n`r`n$($_.Exception.Message)", "导入配置", "OK", "Error") | Out-Null
  }
}

function Reset-SafeDesktopConfiguration {
  $answer = [Windows.MessageBox]::Show(
    "这会停止当前输出、断开设备、清空黑白名单，并恢复低强度固定时长配置。是否继续？",
    "恢复安全默认值",
    "YesNo",
    "Warning")
  if ($answer -ne [Windows.MessageBoxResult]::Yes) { return }
  Set-DesktopConfiguration (Get-SafeDesktopConfiguration) "安全默认值"
  $script:State.Locked = $true
  Add-Log "安全默认值已恢复；为防止误触发，当前保持急停锁定"
  Update-View
}

function Show-AppPage([string]$PageName) {
  $collapsed = [Windows.Visibility]::Collapsed
  $visible = [Windows.Visibility]::Visible
  $DashboardPage.Visibility = $collapsed
  $SettingsPage.Visibility = $collapsed
  $SessionControlPanel.Visibility = $collapsed
  $TriggerStrategyPanel.Visibility = $collapsed
  $CoyoteOutputPanel.Visibility = $collapsed
  $DeviceSafetyPanel.Visibility = $collapsed
  $LowerPages.Visibility = $collapsed
  $ScopeRulesPanel.Visibility = $collapsed
  $LogsPanel.Visibility = $collapsed

  $navButtons = @($NavDashboardButton, $NavScopeButton, $NavTriggerButton, $NavDeviceButton, $NavLogsButton)
  foreach ($button in $navButtons) {
    $button.Background = [Windows.Media.Brushes]::Transparent
  }

  switch ($PageName) {
    "scope" {
      $LowerPages.Visibility = $visible
      $ScopeRulesPanel.Visibility = $visible
      [Windows.Controls.Grid]::SetColumn($ScopeRulesPanel, 0)
      [Windows.Controls.Grid]::SetColumnSpan($ScopeRulesPanel, 2)
      $PageEyebrowValue.Text = "FOCUS SESSION  /  SCOPE RULES"
      $PageTitleValue.Text = "范围规则"
      $activeButton = $NavScopeButton
      Refresh-WindowPicker
    }
    "trigger" {
      $SettingsPage.Visibility = $visible
      $SessionControlPanel.Visibility = $visible
      $TriggerStrategyPanel.Visibility = $visible
      $CoyoteOutputPanel.Visibility = $visible
      $PageEyebrowValue.Text = "FOCUS SESSION  /  TRIGGER PROFILE"
      $PageTitleValue.Text = "触发设置"
      $activeButton = $NavTriggerButton
    }
    "device" {
      $SettingsPage.Visibility = $visible
      $DeviceSafetyPanel.Visibility = $visible
      $PageEyebrowValue.Text = "FOCUS SESSION  /  DEVICE SAFETY"
      $PageTitleValue.Text = "设备与安全"
      $activeButton = $NavDeviceButton
    }
    "logs" {
      $LowerPages.Visibility = $visible
      $LogsPanel.Visibility = $visible
      [Windows.Controls.Grid]::SetColumn($LogsPanel, 0)
      [Windows.Controls.Grid]::SetColumnSpan($LogsPanel, 2)
      $PageEyebrowValue.Text = "FOCUS SESSION  /  EVENT LOG"
      $PageTitleValue.Text = "日志"
      $activeButton = $NavLogsButton
    }
    default {
      $DashboardPage.Visibility = $visible
      $PageEyebrowValue.Text = "FOCUS SESSION  /  DASHBOARD"
      $PageTitleValue.Text = "控制台"
      $activeButton = $NavDashboardButton
    }
  }

  $activeButton.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(45, 140, 255))
  $MainScrollViewer.ScrollToTop()
}

function Initialize-ScopeLists {
  $WhitelistList.Items.Clear()
  $BlacklistList.Items.Clear()
}

function Test-WindowRuleList($Text, $ListBox) {
  foreach ($item in $ListBox.Items) {
    $rule = [string]$item
    if (-not [string]::IsNullOrWhiteSpace($rule) -and $Text -eq $rule) {
      return $rule
    }
  }
  return $null
}

function Get-ForegroundWindowInfo {
  try {
    $handle = [NativeWindowApi]::GetForegroundWindow()
    if ($handle -eq [IntPtr]::Zero) {
      return @{
        Process = "unknown"
        Title = ""
        Display = "unknown"
      }
    }

    $builder = New-Object System.Text.StringBuilder 512
    [void][NativeWindowApi]::GetWindowText($handle, $builder, $builder.Capacity)

    [uint32]$processId = 0
    [void][NativeWindowApi]::GetWindowThreadProcessId($handle, [ref]$processId)
    $processName = "unknown"
    try {
      $process = Get-Process -Id $processId -ErrorAction Stop
      $processName = $process.ProcessName
    } catch {
      $processName = "pid:$processId"
    }

    $title = $builder.ToString()
    return @{
      Process = $processName
      Title = $title
      Display = "$processName | $title"
    }
  } catch {
    return @{
      Process = "unknown"
      Title = ""
      Display = "读取当前窗口失败：$($_.Exception.Message)"
    }
  }
}

function Get-WindowInfoFromHandle([IntPtr]$Handle) {
  $builder = New-Object System.Text.StringBuilder 512
  [void][NativeWindowApi]::GetWindowText($Handle, $builder, $builder.Capacity)
  $title = $builder.ToString().Trim()
  if ([string]::IsNullOrWhiteSpace($title)) {
    return $null
  }

  [uint32]$processId = 0
  [void][NativeWindowApi]::GetWindowThreadProcessId($Handle, [ref]$processId)
  $processName = "unknown"
  try {
    $process = Get-Process -Id $processId -ErrorAction Stop
    $processName = $process.ProcessName
  } catch {
    $processName = "pid:$processId"
  }

  return "$processName | $title"
}

function Refresh-WindowPicker {
  $WindowPickerCombo.Items.Clear()
  $seen = New-Object 'System.Collections.Generic.HashSet[string]'
  $callback = [NativeWindowApi+EnumWindowsProc]{
    param([IntPtr]$hWnd, [IntPtr]$lParam)
    if (-not [NativeWindowApi]::IsWindowVisible($hWnd)) {
      return $true
    }
    $display = Get-WindowInfoFromHandle $hWnd
    if ($null -ne $display -and $seen.Add($display)) {
      [void]$WindowPickerCombo.Items.Add($display)
    }
    return $true
  }
  [void][NativeWindowApi]::EnumWindows($callback, [IntPtr]::Zero)
  if ($WindowPickerCombo.Items.Count -gt 0) {
    $WindowPickerCombo.SelectedIndex = 0
  }
  Add-Log "已刷新窗口列表：$($WindowPickerCombo.Items.Count) 个窗口"
}

function Refresh-CurrentWindow {
  $info = Get-ForegroundWindowInfo
  $CurrentWindowInput.Text = $info.Display
  $display = ([string]$info.Display).Trim()
  if ([string]::IsNullOrWhiteSpace($display) -or $display -eq "unknown") {
    $CurrentWindowMatchValue.Text = "无法识别"
  } elseif ($null -ne (Test-WindowRuleList $display $BlacklistList)) {
    $CurrentWindowMatchValue.Text = "黑名单"
  } elseif ($null -ne (Test-WindowRuleList $display $WhitelistList)) {
    $CurrentWindowMatchValue.Text = "白名单"
  } else {
    $CurrentWindowMatchValue.Text = "未匹配"
  }
  return $info.Display
}

function Apply-CurrentWindowRule($CurrentWindowInfo = $null) {
  if ($null -eq $CurrentWindowInfo) {
    $CurrentWindowInfo = Refresh-CurrentWindow
  }
  $text = ([string]$CurrentWindowInfo).Trim()
  $windowChanged = $script:State.LastWindowKey -ne $text
  if ($windowChanged) {
    $script:State.LastWindowKey = $text
  }
  if ([string]::IsNullOrWhiteSpace($text)) {
    $script:State.WindowState = "left"
    if (-not $script:State.AwayEpisodeActive) {
      $script:State.AwayEpisodeActive = $true
      $script:State.EpisodeTriggerSent = $false
    }
    if ($windowChanged) { Add-Log "当前窗口为空：按未命中处理" }
    return
  }

  $black = Test-WindowRuleList $text $BlacklistList
  if ($null -ne $black) {
    $script:State.WindowState = "blacklist"
    $script:State.LeftSeconds = 0
    $script:State.DistractionSeconds = 0
    if ($windowChanged) { Add-Log "黑名单命中：$black" }
    if (-not $script:State.AwayEpisodeActive) {
      $script:State.AwayEpisodeActive = $true
      $script:State.EpisodeTriggerSent = $false
    }
    if (-not $script:State.EpisodeTriggerSent -and $script:State.Connected) {
      if (Invoke-Trigger "黑名单直接触发") {
        $script:State.EpisodeTriggerSent = $true
      }
    }
    return
  }

  $white = Test-WindowRuleList $text $WhitelistList
  if ($null -ne $white) {
    if ($script:State.OutputActive -and $script:State.OutputHoldUntilWhitelist) {
      Invoke-DeviceStop
    }
    $script:State.WindowState = "writing"
    $script:State.HoldRetriggerPending = $false
    $script:State.HoldCooldownEnd = [DateTime]::MinValue
    $script:State.LeftSeconds = 0
    $script:State.DistractionSeconds = 0
    $script:State.AwayEpisodeActive = $false
    $script:State.EpisodeTriggerSent = $false
    if ($windowChanged) { Add-Log "白名单命中：$white，不处罚" }
    return
  }

  $script:State.WindowState = "left"
  if (-not $script:State.AwayEpisodeActive) {
    $script:State.AwayEpisodeActive = $true
    $script:State.EpisodeTriggerSent = $false
  }
  if ($windowChanged) { Add-Log "未命中黑白名单：按常规离开时间规则处理" }
}

function Get-StatusText {
  if ($script:State.Locked) { return "急停锁定" }
  if (-not $script:State.Running) { return "未开始" }
  if ($script:State.Paused) { return "已暂停" }
  switch ($script:State.WindowState) {
    "writing" { return "写作中" }
    "left" { return "离开中" }
    "blacklist" { return "黑名单命中" }
    "ignore" { return "忽略中" }
    default { return "未知" }
  }
}

function Update-View {
  $StatusValue.Text = Get-StatusText
  $SessionValue.Text = Format-Seconds $script:State.SessionSeconds
  $LeftValue.Text = Format-Seconds $script:State.LeftSeconds
  $DistractionValue.Text = Format-Seconds $script:State.DistractionSeconds
  $IdleValue.Text = Format-Seconds $script:State.IdleSeconds
  if ($script:State.ActualStrengthKnown) {
    $ActualStrengthValue.Text = "A $($script:State.ActualStrengthA)  |  B $($script:State.ActualStrengthB)"
  } else {
    $ActualStrengthValue.Text = "A --  |  B --"
  }
  $ActualStrengthSource.Text = $script:State.ActualStrengthSource
  Update-FloatingMonitor
  if ($script:State.DeviceMode -eq "http") {
    $DeviceValue.Text = if ($script:State.Connected) { "真实桥接已连接" } else { "真实桥接未连接" }
    $DeviceBadge.Text = if ($script:State.Connected) { "真实设备桥接" } else { "真实桥接未连接" }
  } elseif ($script:State.DeviceMode -eq "ble") {
    $DeviceValue.Text = if ($script:State.Connected) { "蓝牙设备已连接" } else { "蓝牙设备未连接" }
    $DeviceBadge.Text = if ($script:State.Connected) { "蓝牙 V3 直连" } else { "蓝牙未连接" }
  } elseif ($script:State.DeviceMode -eq "socket") {
    $registered = -not [string]::IsNullOrWhiteSpace($script:State.SocketClientId)
    $DeviceValue.Text = if ($script:State.Connected) { "Socket App 已绑定" } elseif ($registered) { "等待 App 绑定" } else { "Socket 未连接" }
    $DeviceBadge.Text = if ($script:State.Connected) { "Socket 控制协议" } elseif ($registered) { "Socket 已注册" } else { "Socket 未连接" }
  }
  $LockBadge.Text = if ($script:State.Locked) { "已锁定" } else { "未锁定" }
  $UnlockButton.IsEnabled = $script:State.Locked

  if ($script:State.Locked) {
    $LockBadge.Foreground = [Windows.Media.Brushes]::White
    $LockBadgeBorder.Background = [Windows.Media.Brushes]::IndianRed
  } else {
    $LockBadge.Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(102, 179, 255))
    $LockBadgeBorder.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(37, 56, 74))
  }
}

function Get-ClampedInt($TextBox, [int]$Default, [int]$Minimum, [int]$Maximum) {
  $value = Get-IntText $TextBox $Default
  return [Math]::Max($Minimum, [Math]::Min($Maximum, $value))
}

function Get-NumericRange($TextBox, [int]$DefaultMin, [int]$DefaultMax, [int]$Maximum) {
  $parts = $TextBox.Text -split "-"
  $min = $DefaultMin
  $max = $DefaultMax
  if ($parts.Count -eq 2) {
    [void][int]::TryParse($parts[0].Trim(), [ref]$min)
    [void][int]::TryParse($parts[1].Trim(), [ref]$max)
  }
  $min = [Math]::Max(0, [Math]::Min($Maximum, $min))
  $max = [Math]::Max(0, [Math]::Min($Maximum, $max))
  if ($min -gt $max) {
    $swap = $min
    $min = $max
    $max = $swap
  }
  return @($min, $max)
}

function Convert-WavePeriodToProtocol([int]$PeriodMs) {
  $period = [Math]::Max(10, [Math]::Min(1000, $PeriodMs))
  if ($period -le 100) { return [byte]$period }
  if ($period -le 600) { return [byte]([Math]::Floor(($period - 100) / 5) + 100) }
  return [byte]([Math]::Floor(($period - 600) / 10) + 200)
}

function Get-WaveformData {
  $frequency = Convert-WavePeriodToProtocol (Get-ClampedInt $WavePeriodInput 30 10 1000)
  $wave = Get-ClampedInt $WaveIntensityInput 35 0 100
  switch ($WaveformCombo.SelectedIndex) {
    1 { $levels = @( $wave, 0, $wave, 0 ) }
    2 { $levels = @( [Math]::Round($wave * 0.25), [Math]::Round($wave * 0.5), [Math]::Round($wave * 0.75), $wave ) }
    3 { $levels = @( $wave, [Math]::Round($wave * 0.35), 0, [Math]::Round($wave * 0.7) ) }
    default { $levels = @( $wave, $wave, $wave, $wave ) }
  }
  return @{
    Frequency = [byte[]]@($frequency, $frequency, $frequency, $frequency)
    Intensity = [byte[]]@($levels | ForEach-Object { [byte]$_ })
  }
}

function Get-TriggerProfile {
  $rangeA = Get-NumericRange $StrengthARangeInput 40 60 200
  $rangeB = Get-NumericRange $StrengthBRangeInput 40 60 200
  $channelIndex = $ChannelModeCombo.SelectedIndex
  $aEnabled = $channelIndex -ne 2
  $bEnabled = $channelIndex -ne 1
  $aStrength = if ($aEnabled) { Get-Random -Minimum $rangeA[0] -Maximum ($rangeA[1] + 1) } else { 0 }
  $bStrength = if ($bEnabled) { Get-Random -Minimum $rangeB[0] -Maximum ($rangeB[1] + 1) } else { 0 }
  $channelName = if ($channelIndex -eq 1) { "A" } elseif ($channelIndex -eq 2) { "B" } else { "both" }
  return @{
    AEnabled = $aEnabled
    BEnabled = $bEnabled
    AStrength = $aStrength
    BStrength = $bStrength
    Channel = $channelName
    DurationMs = (Get-ClampedInt $DurationInput 5 1 30) * 1000
    MaxContinuousMs = (Get-ClampedInt $MaxContinuousInput 10 1 30) * 1000
    CooldownMs = (Get-ClampedInt $HoldCooldownInput 60 5 3600) * 1000
    HoldUntilWhitelist = $OutputModeCombo.SelectedIndex -eq 0
    RestartOnRepeat = $OverlapModeCombo.SelectedIndex -eq 0
    WaveformName = @("constant", "pulse", "ramp", "heartbeat")[[Math]::Max(0, [Math]::Min(3, $WaveformCombo.SelectedIndex))]
    WavePeriodMs = Get-ClampedInt $WavePeriodInput 30 10 1000
    WaveIntensity = Get-ClampedInt $WaveIntensityInput 35 0 100
    Waveform = Get-WaveformData
  }
}

function Get-BleSafetyConfig {
  return @{
    SoftLimitA = Get-ClampedInt $SoftLimitAInput 80 0 200
    SoftLimitB = Get-ClampedInt $SoftLimitBInput 80 0 200
    FrequencyBalanceA = Get-ClampedInt $FrequencyBalanceAInput 0 0 255
    FrequencyBalanceB = Get-ClampedInt $FrequencyBalanceBInput 0 0 255
    StrengthBalanceA = Get-ClampedInt $StrengthBalanceAInput 0 0 255
    StrengthBalanceB = Get-ClampedInt $StrengthBalanceBInput 0 0 255
  }
}

function Get-EffectiveStrengthLimits {
  switch ($script:State.DeviceMode) {
    "socket" {
      if (-not $script:State.SocketHasAppLimits) { throw "Socket 尚未收到 App 上报的 A/B 强度上限，已禁止输出。" }
      return @{ A = [int]$script:State.SocketAppLimitA; B = [int]$script:State.SocketAppLimitB; Source = "DG-Lab App" }
    }
    "ble" {
      $safety = Get-BleSafetyConfig
      return @{ A = [int]$safety.SoftLimitA; B = [int]$safety.SoftLimitB; Source = "蓝牙手动" }
    }
    default {
      return @{ A = Get-ClampedInt $HttpLimitAInput 80 0 200; B = Get-ClampedInt $HttpLimitBInput 80 0 200; Source = "HTTP 手动" }
    }
  }
}

function Limit-TriggerProfile($Profile) {
  $limits = Get-EffectiveStrengthLimits
  $requestedA = [int]$Profile.AStrength
  $requestedB = [int]$Profile.BStrength
  $Profile.AStrength = [Math]::Min($requestedA, [int]$limits.A)
  $Profile.BStrength = [Math]::Min($requestedB, [int]$limits.B)
  $Profile.StrengthLimitA = [int]$limits.A
  $Profile.StrengthLimitB = [int]$limits.B
  $Profile.StrengthLimitSource = [string]$limits.Source
  if ($requestedA -ne $Profile.AStrength -or $requestedB -ne $Profile.BStrength) {
    Add-Log "强度已按 $($limits.Source) 上限截断：A $requestedA→$($Profile.AStrength)，B $requestedB→$($Profile.BStrength)"
  }
  return $Profile
}

$script:Ble = @{
  Device = $null
  Service = $null
  WriteCharacteristic = $null
  Sequence = 0
  OutputActive = $false
  OutputEnd = [DateTime]::MinValue
  OutputProfile = $null
  ServiceUuid = [Guid]"0000180c-0000-1000-8000-00805f9b34fb"
  WriteUuid = [Guid]"0000150a-0000-1000-8000-00805f9b34fb"
}

function Await-WinRt($AsyncOperation, [Type]$ResultType) {
  $asTaskMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
      $_.Name -eq "AsTask" -and
      $_.IsGenericMethodDefinition -and
      $_.GetParameters().Count -eq 1
    } |
    Select-Object -First 1
  $task = $asTaskMethod.MakeGenericMethod($ResultType).Invoke($null, @($AsyncOperation))
  $task.Wait()
  return $task.Result
}

function Await-WinRtAction($AsyncAction) {
  $asTaskMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
      $_.Name -eq "AsTask" -and
      -not $_.IsGenericMethodDefinition -and
      $_.GetParameters().Count -eq 1
    } |
    Select-Object -First 1
  $task = $asTaskMethod.Invoke($null, @($AsyncAction))
  $task.Wait()
}

function Convert-BleAddress([string]$InputText) {
  $clean = ($InputText -replace "[^0-9A-Fa-f]", "")
  if ($clean.Length -ne 12) {
    throw "蓝牙模式需要 12 位十六进制蓝牙地址，例如 001A7DDA7113。当前不是有效地址。"
  }
  return [Convert]::ToUInt64($clean, 16)
}

function Build-BleWriter([byte[]]$Bytes) {
  $writer = New-Object Windows.Storage.Streams.DataWriter
  foreach ($byte in $Bytes) {
    $writer.WriteByte($byte)
  }
  return $writer.DetachBuffer()
}

function New-DglabBfPacket {
  $safety = Get-BleSafetyConfig
  return [byte[]]@(
    0xBF,
    [byte]$safety.SoftLimitA, [byte]$safety.SoftLimitB,
    [byte]$safety.FrequencyBalanceA, [byte]$safety.FrequencyBalanceB,
    [byte]$safety.StrengthBalanceA, [byte]$safety.StrengthBalanceB
  )
}

function New-DglabB0Packet($Profile, [switch]$Stop) {
  if ($Stop) {
    $parseMode = [byte]0x0F
    $strengthA = [byte]0
    $strengthB = [byte]0
    $frequencyA = [byte[]]@(10, 10, 10, 10)
    $intensityA = [byte[]]@(0, 0, 0, 0)
    $frequencyB = [byte[]]@(10, 10, 10, 10)
    $intensityB = [byte[]]@(0, 0, 0, 0)
  } else {
    $aMode = if ($Profile.AEnabled) { 0x0C } else { 0x00 }
    $bMode = if ($Profile.BEnabled) { 0x03 } else { 0x00 }
    $parseMode = [byte]($aMode -bor $bMode)
    $strengthA = [byte]$Profile.AStrength
    $strengthB = [byte]$Profile.BStrength
    $frequencyA = if ($Profile.AEnabled) { $Profile.Waveform.Frequency } else { [byte[]]@(10, 10, 10, 10) }
    $intensityA = if ($Profile.AEnabled) { $Profile.Waveform.Intensity } else { [byte[]]@(101, 101, 101, 101) }
    $frequencyB = if ($Profile.BEnabled) { $Profile.Waveform.Frequency } else { [byte[]]@(10, 10, 10, 10) }
    $intensityB = if ($Profile.BEnabled) { $Profile.Waveform.Intensity } else { [byte[]]@(101, 101, 101, 101) }
  }
  return [byte[]]@(
    0xB0, $parseMode, $strengthA, $strengthB,
    $frequencyA[0], $frequencyA[1], $frequencyA[2], $frequencyA[3],
    $intensityA[0], $intensityA[1], $intensityA[2], $intensityA[3],
    $frequencyB[0], $frequencyB[1], $frequencyB[2], $frequencyB[3],
    $intensityB[0], $intensityB[1], $intensityB[2], $intensityB[3]
  )
}

function Initialize-BleTypes {
  [void][Windows.Devices.Bluetooth.BluetoothLEDevice, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]
  [void][Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristic, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]
  [void][Windows.Devices.Bluetooth.GenericAttributeProfile.GattCommunicationStatus, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]
  [void][Windows.Storage.Streams.DataWriter, Windows.Storage.Streams, ContentType = WindowsRuntime]
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
}

function Invoke-BleConnect {
  try {
    Initialize-BleTypes
    $address = Convert-BleAddress $BleAddressInput.Text
    $deviceOp = [Windows.Devices.Bluetooth.BluetoothLEDevice]::FromBluetoothAddressAsync($address)
    $device = Await-WinRt $deviceOp ([Windows.Devices.Bluetooth.BluetoothLEDevice])
    if ($null -eq $device) {
      throw "未找到蓝牙设备。请确认设备已开机、已配对或处于可发现状态。"
    }

    $servicesOp = $device.GetGattServicesForUuidAsync($script:Ble.ServiceUuid)
    $servicesResult = Await-WinRt $servicesOp ([Windows.Devices.Bluetooth.GenericAttributeProfile.GattDeviceServicesResult])
    if ($servicesResult.Status.ToString() -ne "Success" -or $servicesResult.Services.Count -eq 0) {
      throw "未找到 DG-LAB V3 服务 0000180c-0000-1000-8000-00805f9b34fb。"
    }

    $service = $servicesResult.Services[0]
    $charsOp = $service.GetCharacteristicsForUuidAsync($script:Ble.WriteUuid)
    $charsResult = Await-WinRt $charsOp ([Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristicsResult])
    if ($charsResult.Status.ToString() -ne "Success" -or $charsResult.Characteristics.Count -eq 0) {
      throw "未找到写入特征 0000150a-0000-1000-8000-00805f9b34fb。"
    }

    $script:Ble.Device = $device
    $script:Ble.Service = $service
    $script:Ble.WriteCharacteristic = $charsResult.Characteristics[0]
    $script:State.Connected = $true
    Invoke-BleWrite (New-DglabBfPacket)
    $safety = Get-BleSafetyConfig
    Add-Log "蓝牙 V3 设备已连接：$($device.Name)；BF 软上限 A=$($safety.SoftLimitA) B=$($safety.SoftLimitB)"
  } catch {
    $script:State.Connected = $false
    Add-Log "蓝牙连接失败：$($_.Exception.Message)"
  }
}

function Apply-BleSafetySettings {
  if ($script:State.DeviceMode -ne "ble" -or -not $script:State.Connected) {
    Add-Log "BF 参数仅能在蓝牙 V3 已连接时应用"
    return $false
  }
  try {
    Invoke-BleWrite (New-DglabBfPacket)
    $safety = Get-BleSafetyConfig
    Add-Log "已应用 BF：软上限 A=$($safety.SoftLimitA) B=$($safety.SoftLimitB)，频率平衡 A=$($safety.FrequencyBalanceA) B=$($safety.FrequencyBalanceB)，脉宽平衡 A=$($safety.StrengthBalanceA) B=$($safety.StrengthBalanceB)"
    return $true
  } catch {
    Add-Log "BF 参数写入失败：$($_.Exception.Message)"
    return $false
  }
}

function Invoke-BleWrite([byte[]]$Bytes) {
  if ($null -eq $script:Ble.WriteCharacteristic) {
    throw "蓝牙写入特征未连接"
  }
  $buffer = Build-BleWriter $Bytes
  $writeOp = $script:Ble.WriteCharacteristic.WriteValueAsync($buffer)
  $status = Await-WinRt $writeOp ([Windows.Devices.Bluetooth.GenericAttributeProfile.GattCommunicationStatus])
  if ($status.ToString() -ne "Success") {
    throw "蓝牙写入失败：$status"
  }
}

function Invoke-BleStop {
  $script:Ble.OutputActive = $false
  $script:Ble.OutputProfile = $null
  try {
    Invoke-BleWrite (New-DglabB0Packet $null -Stop)
    Set-ActualStrengthState 0 0 "蓝牙已确认下发"
    Add-Log "已将蓝牙 A/B 通道强度归零"
    return $true
  } catch {
    Add-Log "蓝牙停止失败：$($_.Exception.Message)"
    return $false
  }
}

function Invoke-BleActivate($Profile) {
  try {
    $now = Get-Date
    if ($Profile.HoldUntilWhitelist) {
      $endAt = $now.AddMilliseconds($Profile.MaxContinuousMs)
    } elseif ($script:Ble.OutputActive -and -not $Profile.RestartOnRepeat -and $script:Ble.OutputEnd -gt $now) {
      $endAt = $script:Ble.OutputEnd.AddMilliseconds($Profile.DurationMs)
    } else {
      $endAt = $now.AddMilliseconds($Profile.DurationMs)
    }
    Invoke-BleWrite (New-DglabB0Packet $Profile)
    Set-ActualStrengthState ([int]$Profile.AStrength) ([int]$Profile.BStrength) "蓝牙已确认下发"
    $script:Ble.OutputProfile = $Profile
    $script:Ble.OutputEnd = $endAt
    $script:Ble.OutputActive = $true
    return $true
  } catch {
    Add-Log "蓝牙触发失败：$($_.Exception.Message)"
    return $false
  }
}

function Initialize-QrCoder {
  try {
    [void][QRCoder.QRCodeGenerator]
    return
  } catch {
    $localDll = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { "" } else { Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "vendor\QRCoder\QRCoder.dll" }
    if (-not [string]::IsNullOrWhiteSpace($localDll) -and (Test-Path $localDll)) {
      Add-Type -Path $localDll
    } else {
      [void][Reflection.Assembly]::Load("QRCoder")
    }
  }
}

function Set-SocketQrCode([string]$Content) {
  Initialize-QrCoder
  $generator = New-Object QRCoder.QRCodeGenerator
  $data = $generator.CreateQrCode($Content, [QRCoder.QRCodeGenerator+ECCLevel]::M)
  $png = New-Object QRCoder.PngByteQRCode $data
  $bytes = $png.GetGraphic(6)
  $stream = New-Object IO.MemoryStream (,$bytes)
  $bitmap = New-Object Windows.Media.Imaging.BitmapImage
  $bitmap.BeginInit()
  $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
  $bitmap.StreamSource = $stream
  $bitmap.EndInit()
  $bitmap.Freeze()
  $SocketQrImage.Source = $bitmap
  $SocketQrPlaceholder.Visibility = [Windows.Visibility]::Collapsed
  $stream.Dispose()
  $png.Dispose()
  $data.Dispose()
  $generator.Dispose()
}

function Set-SocketBindingInfo([string]$ServerUri, [string]$ClientId) {
  $server = $ServerUri.TrimEnd("/")
  $manualAddress = "$server/$ClientId"
  $qr = "https://www.dungeon-lab.com/app-download.php#DGLAB-SOCKET#$manualAddress"
  $SocketManualAddressText.Text = $manualAddress
  $SocketQrContentText.Text = $qr
  Set-SocketQrCode $qr
}

function Reset-SocketConnection {
  if ($null -ne $script:State.SocketTransport) {
    try { $script:State.SocketTransport.Dispose() } catch {}
  }
  if ($null -ne $script:State.SocketClient) {
    try { $script:State.SocketClient.Abort() } catch {}
    try { $script:State.SocketClient.Dispose() } catch {}
  }
  if ($null -ne $script:State.LocalSocketServer) {
    try { $script:State.LocalSocketServer.Stop() } catch {}
    try { $script:State.LocalSocketServer.Dispose() } catch {}
  }
  $script:State.SocketClient = $null
  $script:State.SocketTransport = $null
  $script:State.LocalSocketServer = $null
  $script:State.LocalSocketLastError = ""
  $script:State.SocketClientId = ""
  $script:State.SocketTargetId = ""
  $script:State.SocketServerUri = ""
  $script:State.SocketReceiveTask = $null
  $script:State.SocketReceiveBuffer = $null
  $script:State.SocketWatchdogStopCount = 0
  $script:State.SocketAppStrengthA = 0
  $script:State.SocketAppStrengthB = 0
  $script:State.SocketAppLimitA = 0
  $script:State.SocketAppLimitB = 0
  $script:State.SocketHasAppLimits = $false
  $script:State.SocketStrengthUpdateCount = 0
  $script:State.Connected = $false
  Set-ActualStrengthState 0 0 "Socket 未连接" $false
  $SocketQrContentText.Text = ""
  $SocketManualAddressText.Text = ""
  $SocketQrImage.Source = $null
  $SocketQrPlaceholder.Visibility = [Windows.Visibility]::Visible
  $SocketBindStatusText.Text = "未连接服务器"
  $SocketAppLimitsText.Text = "等待 App 上报 A/B 强度上限；未上报前禁止输出"
}

function Set-SocketAppStrengthState([int]$StrengthA, [int]$StrengthB, [int]$LimitA, [int]$LimitB) {
  $a = [Math]::Max(0, [Math]::Min(200, $StrengthA))
  $b = [Math]::Max(0, [Math]::Min(200, $StrengthB))
  $limitAValue = [Math]::Max(0, [Math]::Min(200, $LimitA))
  $limitBValue = [Math]::Max(0, [Math]::Min(200, $LimitB))
  $limitsChanged = -not $script:State.SocketHasAppLimits -or $limitAValue -ne $script:State.SocketAppLimitA -or $limitBValue -ne $script:State.SocketAppLimitB
  $script:State.SocketAppStrengthA = $a
  $script:State.SocketAppStrengthB = $b
  $script:State.SocketAppLimitA = $limitAValue
  $script:State.SocketAppLimitB = $limitBValue
  $script:State.SocketHasAppLimits = $true
  $SocketAppLimitsText.Text = "当前 A=$a / 上限 $limitAValue；B=$b / 上限 $limitBValue（来自 App）"
  Set-ActualStrengthState $a $b "Socket App 实时回报"
  if ($limitsChanged) { Add-Log "已读取 DG-Lab App 强度上限：A=$limitAValue，B=$limitBValue" }

  if ($script:State.OutputActive -and $null -ne $script:State.OutputProfile) {
    $newA = [Math]::Min([int]$script:State.OutputProfile.AStrength, $limitAValue)
    $newB = [Math]::Min([int]$script:State.OutputProfile.BStrength, $limitBValue)
    if ($newA -ne $script:State.OutputProfile.AStrength -or $newB -ne $script:State.OutputProfile.BStrength) {
      $script:State.OutputProfile.AStrength = $newA
      $script:State.OutputProfile.BStrength = $newB
      try {
        Invoke-SocketSend "strength-1+2+$newA"
        Invoke-SocketSend "strength-2+2+$newB"
        Add-Log "App 上限降低，活动输出已立即降至 A=$newA，B=$newB"
      } catch {
        Add-Log "App 上限降低但强度下调发送失败，正在立即停止：$($_.Exception.Message)"
        Invoke-SocketStop | Out-Null
      }
    }
  }
}

function Try-ApplySocketStrengthMessage([string]$Body) {
  if ($Body -match '^strength-(\d{1,3})\+(\d{1,3})\+(\d{1,3})\+(\d{1,3})$') {
    Set-SocketAppStrengthState ([int]$Matches[1]) ([int]$Matches[2]) ([int]$Matches[3]) ([int]$Matches[4])
    return $true
  }
  return $false
}

function Start-SocketReceive {
  if ($null -eq $script:State.SocketClient -or $script:State.SocketClient.State -ne [System.Net.WebSockets.WebSocketState]::Open) { return }
  $buffer = New-Object byte[] 4096
  $segment = New-Object 'System.ArraySegment[byte]' (,$buffer)
  $script:State.SocketReceiveBuffer = $buffer
  $script:State.SocketReceiveTask = $script:State.SocketClient.ReceiveAsync($segment, [Threading.CancellationToken]::None)
}

function Update-SocketReceive {
  $task = $script:State.SocketReceiveTask
  if ($null -eq $task -or -not $task.IsCompleted) { return }
  try {
    $result = $task.Result
    if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
      throw "Socket 服务器已关闭连接"
    }
    $json = [Text.Encoding]::UTF8.GetString($script:State.SocketReceiveBuffer, 0, $result.Count)
    $message = $json | ConvertFrom-Json
    if ($message.type -eq "bind" -and $message.message -eq "targetId") {
      $script:State.SocketClientId = [string]$message.clientId
      if ($null -ne $script:State.SocketTransport) { $script:State.SocketTransport.UpdateBinding($script:State.SocketClientId, "") }
      Set-SocketBindingInfo $script:State.SocketServerUri $script:State.SocketClientId
      $SocketBindStatusText.Text = "服务器已注册，等待 App 扫码或手动连接"
      Add-Log "Socket 终端已注册，等待 App 绑定：$($script:State.SocketClientId)"
    } elseif ($message.type -eq "bind" -and [string]$message.message -eq "200" -and [string]$message.clientId -eq $script:State.SocketClientId) {
      $script:State.SocketTargetId = [string]$message.targetId
      $script:State.SocketHasAppLimits = $false
      $SocketAppLimitsText.Text = "App 已绑定，等待上报 A/B 强度上限；当前禁止输出"
      if ($null -ne $script:State.SocketTransport) { $script:State.SocketTransport.UpdateBinding($script:State.SocketClientId, $script:State.SocketTargetId) }
      $script:State.Connected = $true
      $SocketBindStatusText.Text = "App 已绑定，可以发送控制指令"
      Add-Log "Socket App 已绑定：$($script:State.SocketTargetId)"
    } elseif ($message.type -eq "msg" -and $script:State.Connected -and
      [string]$message.clientId -eq $script:State.SocketTargetId -and
      [string]$message.targetId -eq $script:State.SocketClientId) {
      [void](Try-ApplySocketStrengthMessage ([string]$message.message))
    } elseif ($message.type -eq "break") {
      $script:State.Connected = $false
      $script:State.SocketTargetId = ""
      $script:State.SocketHasAppLimits = $false
      $SocketAppLimitsText.Text = "等待 App 上报 A/B 强度上限；未上报前禁止输出"
      $SocketBindStatusText.Text = "App 已断开，请重新扫码绑定"
      Add-Log "Socket App 已断开"
    }
    Start-SocketReceive
  } catch {
    Add-Log "Socket 接收失败：$($_.Exception.Message)"
    Reset-SocketConnection
  }
}

function Get-PreferredLocalIpv4Address {
  $addresses = [Net.Dns]::GetHostAddresses([Net.Dns]::GetHostName()) | Where-Object {
    $_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and -not [Net.IPAddress]::IsLoopback($_)
  }
  $preferred = $addresses | Where-Object { $_.ToString() -match '^(192\.168\.|10\.|169\.254\.|172\.(1[6-9]|2[0-9]|3[01])\.)' } | Select-Object -First 1
  if ($null -eq $preferred) { return "127.0.0.1" }
  return $preferred.ToString()
}

function Invoke-LocalSocketStart {
  try {
    Reset-SocketConnection
    $hostText = $LocalSocketHostInput.Text.Trim()
    $port = Get-ClampedInt $LocalSocketPortInput 5678 1 65535
    $advertisedUri = Assert-SecureNetworkEndpoint "ws://$hostText`:$port" "socket"
    $server = New-Object LocalDglabSocketServer
    $server.Start($advertisedUri.DnsSafeHost, $port)
    $script:State.LocalSocketServer = $server
    $script:State.SocketClientId = $server.ClientId
    $script:State.SocketServerUri = $advertisedUri.AbsoluteUri.TrimEnd("/")
    Set-SocketBindingInfo $script:State.SocketServerUri $script:State.SocketClientId
    $SocketBindStatusText.Text = "本地服务器已启动，等待 App 扫码或手动连接"
    Add-Log "本地 Socket 服务器已安全绑定：$($advertisedUri.DnsSafeHost):$port"
  } catch {
    Reset-SocketConnection
    Add-Log "本地 Socket 服务器启动失败：$($_.Exception.Message)"
  }
}

function Update-LocalSocketServer {
  $server = $script:State.LocalSocketServer
  if ($null -eq $server) { return }
  if (-not [string]::IsNullOrWhiteSpace($server.LastError) -and $server.LastError -ne $script:State.LocalSocketLastError) {
    $script:State.LocalSocketLastError = $server.LastError
    Add-Log "本地 Socket 服务器错误：$($server.LastError)"
  }
  if ($server.IsBound -and -not $script:State.Connected) {
    $script:State.SocketTargetId = $server.TargetId
    $script:State.Connected = $true
    $script:State.SocketHasAppLimits = $false
    $SocketAppLimitsText.Text = "App 已绑定，等待上报 A/B 强度上限；当前禁止输出"
    $SocketBindStatusText.Text = "App 已绑定本地服务器，等待强度上限"
    Add-Log "Socket App 已绑定本地服务器：$($script:State.SocketTargetId)"
  } elseif (-not $server.IsBound -and $script:State.Connected) {
    $script:State.Connected = $false
    $script:State.SocketTargetId = ""
    $script:State.SocketHasAppLimits = $false
    $SocketAppLimitsText.Text = "等待 App 上报 A/B 强度上限；未上报前禁止输出"
    $SocketBindStatusText.Text = "App 已断开，请重新扫码绑定"
    Add-Log "Socket App 已从本地服务器断开"
  }
  if ($server.HasAppLimits -and $server.StrengthUpdateCount -ne $script:State.SocketStrengthUpdateCount) {
    $script:State.SocketStrengthUpdateCount = $server.StrengthUpdateCount
    Set-SocketAppStrengthState $server.AppStrengthA $server.AppStrengthB $server.AppLimitA $server.AppLimitB
  }
}

function Invoke-RemoteSocketConnect {
  try {
    Reset-SocketConnection
    $uri = Assert-SecureNetworkEndpoint $SocketServerInput.Text "socket"
    $text = $uri.AbsoluteUri.TrimEnd("/")
    $client = New-Object System.Net.WebSockets.ClientWebSocket
    $connectTimeout = New-Object Threading.CancellationTokenSource 5000
    try {
      $client.ConnectAsync($uri, $connectTimeout.Token).Wait()
    } finally {
      $connectTimeout.Dispose()
    }
    if ($client.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
      throw "Socket 连接未进入 Open 状态。"
    }
    $script:State.SocketClient = $client
    $script:State.SocketTransport = New-Object DglabRemoteSocketTransport $client
    $script:State.SocketServerUri = $text
    $SocketBindStatusText.Text = "服务器已连接，正在注册终端…"
    Start-SocketReceive
    Add-Log "Socket 服务器已连接，等待注册消息：$text"
  } catch {
    Reset-SocketConnection
    Add-Log "Socket 连接失败：$($_.Exception.Message)"
  }
}

function Invoke-SocketConnect {
  if ($script:State.SocketServerMode -eq "local") {
    Invoke-LocalSocketStart
  } else {
    Invoke-RemoteSocketConnect
  }
}

function Invoke-SocketSend([string]$Command) {
  if (-not $script:State.Connected -or [string]::IsNullOrWhiteSpace($script:State.SocketClientId) -or [string]::IsNullOrWhiteSpace($script:State.SocketTargetId)) {
    throw "Socket App 尚未完成绑定"
  }
  if ($null -ne $script:State.LocalSocketServer) {
    $script:State.LocalSocketServer.SendCommand($Command)
    return
  }
  if ($null -eq $script:State.SocketTransport) { throw "Socket 安全传输器未初始化" }
  $script:State.SocketTransport.SendCommand($Command)
}

function Invoke-SocketStop {
  $transport = if ($null -ne $script:State.LocalSocketServer) { $script:State.LocalSocketServer } else { $script:State.SocketTransport }
  if ($null -eq $transport) {
    Add-Log "Socket 停止失败：安全传输器不可用"
    return $false
  }
  try {
    $stopped = $transport.StopOutputReliable(3)
    if ($stopped) {
      $transport.CancelSafetyTimeout()
      Set-ActualStrengthState 0 0 "Socket 停止命令已下发"
      Add-Log "Socket A/B 已归零并清除波形（独立命令、最多重试 3 次）"
      return $true
    }
    Add-Log "Socket 停止未全部成功：$($transport.LastError)；后台看门狗仍保持待命"
    return $false
  } catch {
    Add-Log "Socket 停止异常：$($_.Exception.Message)；后台看门狗仍保持待命"
    return $false
  }
}

function Arm-SocketSafetyWatchdog([int]$TimeoutMs) {
  $transport = if ($null -ne $script:State.LocalSocketServer) { $script:State.LocalSocketServer } else { $script:State.SocketTransport }
  if ($null -eq $transport) { throw "Socket 安全看门狗不可用" }
  $transport.ArmSafetyTimeout($TimeoutMs)
  $script:State.SocketWatchdogStopCount = $transport.WatchdogStopCount
}

function Update-SocketSafetyWatchdogStatus {
  $transport = if ($null -ne $script:State.LocalSocketServer) { $script:State.LocalSocketServer } else { $script:State.SocketTransport }
  if ($null -eq $transport) { return }
  if ($transport.WatchdogStopCount -gt $script:State.SocketWatchdogStopCount) {
    $script:State.SocketWatchdogStopCount = $transport.WatchdogStopCount
    if ($transport.LastWatchdogStopSucceeded) {
      Set-ActualStrengthState 0 0 "Socket 看门狗已下发"
      Add-Log "Socket 后台安全看门狗已独立执行 A/B 归零"
    } else {
      Add-Log "警告：Socket 后台安全看门狗未能完成全部停止命令：$($transport.LastError)"
    }
  }
}

function Invoke-SocketActivate($Profile) {
  try {
    $Profile = Limit-TriggerProfile $Profile
    $a = if ($Profile.Channel -in @("A", "both")) { $Profile.AStrength } else { 0 }
    $b = if ($Profile.Channel -in @("B", "both")) { $Profile.BStrength } else { 0 }
    Invoke-SocketSend "clear-1"
    Invoke-SocketSend "clear-2"
    Invoke-SocketSend "strength-1+2+$a"
    Invoke-SocketSend "strength-2+2+$b"
    Set-ActualStrengthState $a $b "Socket 已下发，等待 App 回报"
    return $true
  } catch {
    Add-Log "Socket 触发失败：$($_.Exception.Message)"
    return $false
  }
}

function Get-EndpointUrl($Action) {
  $baseUri = Assert-SecureNetworkEndpoint $HttpEndpointInput.Text "http"
  $base = $baseUri.AbsoluteUri.TrimEnd("/")
  if ($base -match "/(activate|stop|status)$") {
    return ($base -replace "/(activate|stop|status)$", "/$Action")
  }
  return "$base/$Action"
}

function Invoke-DeviceStatus {
  if ($script:State.DeviceMode -eq "ble") {
    Invoke-BleConnect
    return
  }
  if ($script:State.DeviceMode -eq "socket") {
    Invoke-SocketConnect
    return
  }

  try {
    $url = Get-EndpointUrl "status"
    Invoke-RestMethod -Method Get -Uri $url -TimeoutSec 5 | Out-Null
    $script:State.Connected = $true
    Add-Log "真实设备桥接已连接：$url"
  } catch {
    $script:State.Connected = $false
    Add-Log "真实设备桥接连接失败：$($_.Exception.Message)"
  }
}

function Invoke-DeviceStop {
  $script:State.OutputActive = $false
  $script:State.OutputHoldUntilWhitelist = $false
  $script:State.OutputProfile = $null
  $script:State.OutputEnd = [DateTime]::MinValue
  $script:State.HoldRetriggerPending = $false
  $script:State.HoldCooldownEnd = [DateTime]::MinValue
  $script:State.HttpRenewAt = [DateTime]::MinValue
  if ($script:State.DeviceMode -eq "ble") {
    return Invoke-BleStop
  }
  if ($script:State.DeviceMode -eq "socket") {
    return Invoke-SocketStop
  }

  try {
    $url = Get-EndpointUrl "stop"
    $body = @{ action = "stop" } | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body $body -TimeoutSec 5 | Out-Null
    Set-ActualStrengthState 0 0 "HTTP 桥接已确认接收"
    Add-Log "已发送真实设备停止指令"
    return $true
  } catch {
    Add-Log "真实设备停止失败：$($_.Exception.Message)"
    return $false
  }
}

function Invoke-HttpActivate($Profile) {
  try {
    $url = Get-EndpointUrl "activate"
    $legacyIntensity = [Math]::Max($Profile.AStrength, $Profile.BStrength)
    $duration = if ($Profile.HoldUntilWhitelist) { $Profile.MaxContinuousMs } else { $Profile.DurationMs }
    $limits = Get-EffectiveStrengthLimits
    $body = @{
      action = "activate"
      intensity = $legacyIntensity
      intensityA = $Profile.AStrength
      intensityB = $Profile.BStrength
      durationMs = $duration
      channel = $Profile.Channel
      pattern = $Profile.WaveformName
      pulseId = $Profile.WaveformName
      overrides = $Profile.RestartOnRepeat
      wavePeriodMs = $Profile.WavePeriodMs
      waveIntensity = $Profile.WaveIntensity
      softLimitA = $limits.A
      softLimitB = $limits.B
    } | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body $body -TimeoutSec 5 | Out-Null
    Set-ActualStrengthState ([int]$Profile.AStrength) ([int]$Profile.BStrength) "HTTP 桥接已确认接收"
    return $true
  } catch {
    Add-Log "真实设备触发失败：$($_.Exception.Message)"
    return $false
  }
}

function Invoke-DeviceActivate($Profile) {
  if ($script:State.DeviceMode -eq "ble") {
    return Invoke-BleActivate $Profile
  }
  if ($script:State.DeviceMode -eq "socket") {
    return Invoke-SocketActivate $Profile
  }
  return Invoke-HttpActivate $Profile
}

function Invoke-Trigger($Reason) {
  if ($script:State.Locked) {
    Add-Log "触发被拦截：安全锁定"
    return $false
  }
  if (-not $script:State.Connected) {
    Add-Log "触发被拦截：设备未连接"
    return $false
  }
  $profile = Get-TriggerProfile
  try { $profile = Limit-TriggerProfile $profile }
  catch {
    Add-Log "触发被拦截：$($_.Exception.Message)"
    return $false
  }
  if ($Reason -notin @("黑名单直接触发", "离开写作范围", "冷却结束仍未返回白名单")) {
    $profile.HoldUntilWhitelist = $false
  }
  $sent = Invoke-DeviceActivate $profile
  if (-not $sent) {
    return $false
  }

  $activeDurationMs = if ($profile.HoldUntilWhitelist) { $profile.MaxContinuousMs } else { $profile.DurationMs }
  if ($script:State.DeviceMode -eq "socket") {
    try { Arm-SocketSafetyWatchdog $activeDurationMs }
    catch {
      Add-Log "Socket 安全看门狗启动失败，已立即停止输出：$($_.Exception.Message)"
      Invoke-SocketStop | Out-Null
      return $false
    }
  }

  $script:State.OutputActive = $true
  $script:State.OutputHoldUntilWhitelist = $profile.HoldUntilWhitelist
  $script:State.OutputProfile = $profile
  $script:State.OutputEnd = (Get-Date).AddMilliseconds($activeDurationMs)
  $script:State.HoldRetriggerPending = $false
  $script:State.HoldCooldownEnd = [DateTime]::MinValue
  $script:State.HttpRenewAt = [DateTime]::MinValue

  $prefix = if ($script:State.DeviceMode -eq "ble") { "蓝牙输出" } else { "HTTP 输出" }
  $durationText = if ($profile.HoldUntilWhitelist) { "最长 $([int]($profile.MaxContinuousMs / 1000)) 秒，随后冷却 $([int]($profile.CooldownMs / 1000)) 秒" } else { "$([int]($profile.DurationMs / 1000)) 秒" }
  Add-Log "$Reason：$prefix 通道 $($profile.Channel)，A=$($profile.AStrength) B=$($profile.BStrength)，波形 $($profile.WaveformName)，$durationText"
  Update-View
  return $true
}

$NavDashboardButton.Add_Click({ Show-AppPage "dashboard" })
$NavScopeButton.Add_Click({ Show-AppPage "scope" })
$NavTriggerButton.Add_Click({ Show-AppPage "trigger" })
$NavDeviceButton.Add_Click({ Show-AppPage "device" })
$NavLogsButton.Add_Click({ Show-AppPage "logs" })

$StartButton.Add_Click({
  if ($script:State.OutputActive) { Invoke-DeviceStop | Out-Null }
  $focusMinutes = Get-IntText $FocusMinutesInput 45
  if ($focusMinutes -lt 1 -or $focusMinutes -gt 10080) {
    $focusMinutes = 45
    $FocusMinutesInput.Text = "45"
    Add-Log "专注时长需为 1 至 10080 分钟，已恢复为 45 分钟"
  }
  $script:State.Running = $true
  $script:State.Paused = $false
  $script:State.SessionSeconds = $focusMinutes * 60
  $script:State.LeftSeconds = 0
  $script:State.DistractionSeconds = 0
  $script:State.IdleSeconds = 0
  $script:State.IdleTriggerSent = $false
  $script:State.FocusStartedAt = Get-Date
  $script:State.AwayEpisodeActive = $false
  $script:State.EpisodeTriggerSent = $false
  Add-Log "专注周期已开始：$focusMinutes 分钟"
  Update-View
})

$PauseButton.Add_Click({
  if ($script:State.Running) {
    $script:State.Paused = -not $script:State.Paused
    if ($script:State.Paused) {
      if ($script:State.OutputActive) { Invoke-DeviceStop | Out-Null }
      Add-Log "专注已暂停，活动输出已停止"
    } else {
      $script:State.IdleSeconds = 0
      $script:State.IdleTriggerSent = $false
      $script:State.FocusStartedAt = Get-Date
      Add-Log "专注已恢复"
    }
    Update-View
  }
})

$EndButton.Add_Click({
  if ($script:State.OutputActive) { Invoke-DeviceStop | Out-Null }
  $script:State.Running = $false
  $script:State.Paused = $false
  $script:State.LeftSeconds = 0
  $script:State.DistractionSeconds = 0
  $script:State.IdleSeconds = 0
  $script:State.IdleTriggerSent = $false
  $script:State.FocusStartedAt = [DateTime]::MinValue
  $script:State.AwayEpisodeActive = $false
  $script:State.EpisodeTriggerSent = $false
  Add-Log "专注周期已结束"
  Update-View
})

$EmergencyButton.Add_Click({
  if ($script:State.Connected) { Invoke-DeviceStop | Out-Null }
  $script:State.Locked = $true
  Add-Log "急停已执行，设备输出停止"
  Update-View
})

$UnlockButton.Add_Click({
  $script:State.Locked = $false
  Add-Log "安全锁定已解除"
  Update-View
})

$ManualTestButton.Add_Click({ Invoke-Trigger "手动测试" })
$FloatingMonitorButton.Add_Click({ Toggle-FloatingMonitor })
$SocketServerModeCombo.Add_SelectionChanged({
  if ($null -ne $script:State.SocketClient -or $null -ne $script:State.LocalSocketServer) { Reset-SocketConnection }
  if ($SocketServerModeCombo.SelectedIndex -eq 0) {
    $script:State.SocketServerMode = "local"
    $LocalSocketSettings.Visibility = [Windows.Visibility]::Visible
    $RemoteSocketSettings.Visibility = [Windows.Visibility]::Collapsed
    $ConnectButton.Content = "启动本地服务器并生成二维码"
    Add-Log "Socket 已切换到本地服务器模式"
  } else {
    $script:State.SocketServerMode = "remote"
    $LocalSocketSettings.Visibility = [Windows.Visibility]::Collapsed
    $RemoteSocketSettings.Visibility = [Windows.Visibility]::Visible
    $ConnectButton.Content = "连接外部服务器并生成二维码"
    Add-Log "Socket 已切换到外部服务器模式"
  }
  Update-View
})
$DeviceModeCombo.Add_SelectionChanged({
  if ($script:State.OutputActive -and $script:State.Connected) { Invoke-DeviceStop | Out-Null }
  if ($null -ne $script:State.SocketClient -or $null -ne $script:State.LocalSocketServer) { Reset-SocketConnection }
  Set-ActualStrengthState 0 0 "设备模式已切换，等待连接" $false
  $HttpConnectionPage.Visibility = [Windows.Visibility]::Collapsed
  $BleConnectionPage.Visibility = [Windows.Visibility]::Collapsed
  $SocketConnectionPage.Visibility = [Windows.Visibility]::Collapsed
  if ($DeviceModeCombo.SelectedIndex -eq 2) {
    $script:State.DeviceMode = "socket"
    $script:State.Connected = $false
    $SocketConnectionPage.Visibility = [Windows.Visibility]::Visible
    $ConnectButton.Content = if ($script:State.SocketServerMode -eq "local") { "启动本地服务器并生成二维码" } else { "连接外部服务器并生成二维码" }
    $ApplySafetyButton.Visibility = [Windows.Visibility]::Collapsed
    Add-Log "已切换到 Socket 控制协议模式"
  } elseif ($DeviceModeCombo.SelectedIndex -eq 1) {
    $script:State.DeviceMode = "ble"
    $script:State.Connected = $false
    $BleConnectionPage.Visibility = [Windows.Visibility]::Visible
    $ConnectButton.Content = "连接并应用安全参数"
    $ApplySafetyButton.Visibility = [Windows.Visibility]::Visible
    Add-Log "已切换到蓝牙 V3 直连模式"
  } else {
    $script:State.DeviceMode = "http"
    $script:State.Connected = $false
    $HttpConnectionPage.Visibility = [Windows.Visibility]::Visible
    $ConnectButton.Content = "连接 HTTP 桥接"
    $ApplySafetyButton.Visibility = [Windows.Visibility]::Collapsed
    Add-Log "已切换到 HTTP 真实设备桥接模式"
  }
  Update-View
})
$ConnectButton.Add_Click({ Invoke-DeviceStatus; Update-View })
$ApplySafetyButton.Add_Click({ Apply-BleSafetySettings | Out-Null; Update-View })
$DisconnectButton.Add_Click({
  if ($script:State.Connected) { Invoke-DeviceStop | Out-Null }
  if ($null -ne $script:State.SocketClient -or $null -ne $script:State.LocalSocketServer) { Reset-SocketConnection }
  $script:State.Connected = $false
  $script:Ble.WriteCharacteristic = $null
  $script:Ble.Service = $null
  $script:Ble.Device = $null
  Set-ActualStrengthState 0 0 "设备已断开" $false
  Add-Log "设备连接已断开"
  Update-View
})
$StopButton.Add_Click({ Invoke-DeviceStop; Update-View })
$ClearLogsButton.Add_Click({ $LogList.Items.Clear() })
$ImportConfigButton.Add_Click({ Import-DesktopConfiguration })
$ExportConfigButton.Add_Click({
  try { Export-DesktopConfiguration }
  catch {
    Add-Log "配置导出失败：$($_.Exception.Message)"
    [Windows.MessageBox]::Show("配置导出失败：`r`n`r`n$($_.Exception.Message)", "导出配置", "OK", "Error") | Out-Null
  }
})
$ResetSafeConfigButton.Add_Click({ Reset-SafeDesktopConfiguration })

$RefreshWindowListButton.Add_Click({
  Refresh-WindowPicker
})

$AddWhitelistButton.Add_Click({
  $value = [string]$WindowPickerCombo.SelectedItem
  if (-not [string]::IsNullOrWhiteSpace($value)) {
    if (-not $WhitelistList.Items.Contains($value)) {
      [void]$WhitelistList.Items.Add($value)
      Add-Log "已添加窗口白名单：$value"
    }
  }
  Refresh-CurrentWindow | Out-Null
  Update-View
})

$RemoveWhitelistButton.Add_Click({
  if ($WhitelistList.SelectedIndex -ge 0) {
    $value = [string]$WhitelistList.SelectedItem
    $WhitelistList.Items.RemoveAt($WhitelistList.SelectedIndex)
    Add-Log "已删除白名单：$value"
  }
  Refresh-CurrentWindow | Out-Null
})

$AddBlacklistButton.Add_Click({
  $value = [string]$WindowPickerCombo.SelectedItem
  if (-not [string]::IsNullOrWhiteSpace($value)) {
    if (-not $BlacklistList.Items.Contains($value)) {
      [void]$BlacklistList.Items.Add($value)
      Add-Log "已添加窗口黑名单：$value"
    }
  }
  Refresh-CurrentWindow | Out-Null
  Update-View
})

$RemoveBlacklistButton.Add_Click({
  if ($BlacklistList.SelectedIndex -ge 0) {
    $value = [string]$BlacklistList.SelectedItem
    $BlacklistList.Items.RemoveAt($BlacklistList.SelectedIndex)
    Add-Log "已删除黑名单：$value"
  }
  Refresh-CurrentWindow | Out-Null
})

function Update-OutputExpiration {
  if (-not $script:State.OutputActive -or (Get-Date) -lt $script:State.OutputEnd) {
    return
  }
  $wasHoldMode = $script:State.OutputHoldUntilWhitelist
  $expiredProfile = $script:State.OutputProfile
  Invoke-DeviceStop | Out-Null
  if ($wasHoldMode -and $null -ne $expiredProfile -and $script:State.WindowState -in @("left", "blacklist")) {
    $script:State.HoldRetriggerPending = $true
    $script:State.HoldCooldownEnd = (Get-Date).AddMilliseconds($expiredProfile.CooldownMs)
    Add-Log "已达到最长连续输出时间并停止；进入 $([int]($expiredProfile.CooldownMs / 1000)) 秒冷却期"
  }
}

function Update-HoldCooldown {
  if (-not $script:State.HoldRetriggerPending) { return }
  if ($script:State.WindowState -eq "writing" -or -not $script:State.Running -or $script:State.Paused -or $script:State.Locked) {
    $script:State.HoldRetriggerPending = $false
    $script:State.HoldCooldownEnd = [DateTime]::MinValue
    return
  }
  if ((Get-Date) -lt $script:State.HoldCooldownEnd) { return }
  if ($script:State.WindowState -notin @("left", "blacklist") -or -not $script:State.Connected) {
    $script:State.HoldCooldownEnd = (Get-Date).AddSeconds(5)
    return
  }
  $script:State.HoldRetriggerPending = $false
  if (-not (Invoke-Trigger "冷却结束仍未返回白名单")) {
    $script:State.HoldRetriggerPending = $true
    $script:State.HoldCooldownEnd = (Get-Date).AddSeconds(5)
  }
}

$bleOutputTimer = New-Object Windows.Threading.DispatcherTimer
$bleOutputTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$bleOutputTimer.Add_Tick({
  if (-not $script:Ble.OutputActive) { return }
  Update-OutputExpiration
  if (-not $script:Ble.OutputActive) { return }
  if (-not $script:State.Connected -or $script:State.Locked) {
    Invoke-DeviceStop | Out-Null
    return
  }
  try {
    Invoke-BleWrite (New-DglabB0Packet $script:Ble.OutputProfile)
  } catch {
    Add-Log "蓝牙连续波形发送失败：$($_.Exception.Message)"
    $script:State.Connected = $false
    $script:Ble.OutputActive = $false
    $script:State.OutputActive = $false
  }
})
$bleOutputTimer.Start()

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
  if ($script:State.DeviceMode -eq "socket") {
    if ($null -ne $script:State.LocalSocketServer) { Update-LocalSocketServer } else { Update-SocketReceive }
    Update-SocketSafetyWatchdogStatus
  }
  # 当前前台窗口展示与专注会话解耦，任何状态下都保持实时更新。
  $currentWindowInfo = Refresh-CurrentWindow
  if ($script:State.Running -and -not $script:State.Paused -and -not $script:State.Locked) {
    Apply-CurrentWindowRule $currentWindowInfo
    if ($script:State.SessionSeconds -gt 0) { $script:State.SessionSeconds -= 1 }
    $previousIdleSeconds = $script:State.IdleSeconds
    $systemIdleSeconds = Get-SystemIdleSeconds
    $sessionAgeSeconds = [int][Math]::Floor(((Get-Date) - $script:State.FocusStartedAt).TotalSeconds)
    $script:State.IdleSeconds = [Math]::Max(0, [Math]::Min($systemIdleSeconds, $sessionAgeSeconds))
    if ($script:State.IdleSeconds -lt $previousIdleSeconds) {
      $script:State.IdleTriggerSent = $false
    }

    switch ($script:State.WindowState) {
      "writing" {
        $script:State.LeftSeconds = 0
        $script:State.DistractionSeconds = 0
      }
      "left" {
        $script:State.LeftSeconds += 1
        $script:State.DistractionSeconds = 0
      }
      "blacklist" {
        $script:State.LeftSeconds = 0
        $script:State.DistractionSeconds = 0
      }
      "ignore" {
        $script:State.LeftSeconds = 0
        $script:State.DistractionSeconds = 0
      }
    }

    $leaveSeconds = Get-IntText $LeaveInput 300
    if ($script:State.AwayEpisodeActive -and -not $script:State.EpisodeTriggerSent -and $script:State.WindowState -eq "left" -and $script:State.LeftSeconds -ge $leaveSeconds -and $script:State.Connected) {
      if (Invoke-Trigger "离开写作范围") {
        $script:State.EpisodeTriggerSent = $true
      }
    }
    $idleTriggerSeconds = Get-ClampedInt $IdleInput 600 1 86400
    if (-not $script:State.IdleTriggerSent -and $script:State.IdleSeconds -ge $idleTriggerSeconds -and $script:State.Connected) {
      if (Invoke-Trigger "长时间无输入") {
        $script:State.IdleTriggerSent = $true
      }
    }
    if ($script:State.SessionSeconds -eq 0) {
      Invoke-Trigger "专注周期结束"
      $script:State.Running = $false
      $script:State.Paused = $false
      Add-Log "专注周期计时完成"
    }
  }

  Update-OutputExpiration
  Update-HoldCooldown
  Update-View
})

$floatingMonitorTimer = New-Object Windows.Threading.DispatcherTimer
$floatingMonitorTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$floatingMonitorTimer.Add_Tick({ Update-FloatingMonitor })

$window.Add_Closing({
  $timer.Stop()
  $bleOutputTimer.Stop()
  $floatingMonitorTimer.Stop()
  if ($null -ne $script:FloatingMonitorWindow) {
    $script:FloatingMonitorWindow.Close()
  }
  if ($script:State.Connected) {
    Invoke-DeviceStop | Out-Null
  }
  if ($null -ne $script:State.SocketClient -or $null -ne $script:State.LocalSocketServer) { Reset-SocketConnection }
})

$timer.Start()
$floatingMonitorTimer.Start()
$LocalSocketHostInput.Text = Get-PreferredLocalIpv4Address
Initialize-ScopeLists
Show-AppPage "dashboard"
Refresh-CurrentWindow | Out-Null
Refresh-WindowPicker
Add-Log "桌面应用已启动"
Update-View
if ($env:OC_WRITING_FOCUS_SELF_TEST -eq "1") {
  $timer.Stop()
  $bleOutputTimer.Stop()
  $floatingMonitorTimer.Stop()
  foreach ($allowedEndpoint in @(
    @{ Text = "https://device.example.com"; Kind = "http" },
    @{ Text = "http://127.0.0.1:8080"; Kind = "http" },
    @{ Text = "http://192.168.1.20:8080"; Kind = "http" },
    @{ Text = "wss://socket.example.com"; Kind = "socket" },
    @{ Text = "ws://10.0.0.20:5678"; Kind = "socket" }
  )) {
    [void](Assert-SecureNetworkEndpoint $allowedEndpoint.Text $allowedEndpoint.Kind)
  }
  foreach ($rejectedEndpoint in @(
    @{ Text = "http://example.com"; Kind = "http" },
    @{ Text = "ws://8.8.8.8:5678"; Kind = "socket" },
    @{ Text = "http://user:password@127.0.0.1:8080"; Kind = "http" },
    @{ Text = "wss://socket.example.com/connect?token=secret"; Kind = "socket" }
  )) {
    $endpointRejected = $false
    try { [void](Assert-SecureNetworkEndpoint $rejectedEndpoint.Text $rejectedEndpoint.Kind) } catch { $endpointRejected = $true }
    if (-not $endpointRejected) { throw "不安全网络地址未被拒绝：$($rejectedEndpoint.Text)" }
  }
  Set-DesktopConfiguration (Get-SafeDesktopConfiguration) "自动测试安全默认值"
  $roundTrip = ((Get-DesktopConfiguration) | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
  Set-DesktopConfiguration $roundTrip "自动测试往返配置"
  if ($roundTrip.schemaVersion -ne 2 -or $roundTrip.trigger.outputMode -ne "fixedDuration" -or $roundTrip.trigger.durationSeconds -ne 1) {
    throw "配置 JSON 往返测试失败"
  }
  if ($StrengthARangeInput.Text -ne "10-20" -or $SoftLimitAInput.Text -ne "30" -or $HttpLimitAInput.Text -ne "30" -or $DurationInput.Text -ne "1" -or $MaxContinuousInput.Text -ne "10" -or $HoldCooldownInput.Text -ne "60") {
    throw "安全默认值应用测试失败"
  }
  $legacyConfig = ($roundTrip | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
  $legacyConfig.schemaVersion = 1
  $legacyConfig.trigger | Add-Member -NotePropertyName durationMs -NotePropertyValue 1500
  $legacyConfig.trigger.PSObject.Properties.Remove("durationSeconds")
  Set-DesktopConfiguration $legacyConfig "自动测试旧版配置"
  if ($DurationInput.Text -ne "2" -or (Get-TriggerProfile).DurationMs -ne 2000) {
    throw "旧版毫秒配置转换或秒到毫秒内部换算失败"
  }
  $invalidRejected = $false
  try {
    $roundTrip.trigger.durationSeconds = 999999
    Set-DesktopConfiguration $roundTrip "无效配置"
  } catch {
    $invalidRejected = $true
  }
  if (-not $invalidRejected) { throw "无效配置未被拒绝" }
  Set-ActualStrengthState 17 23 "自动测试"
  if ($ActualStrengthValue.Text -ne "A 17  |  B 23" -or $ActualStrengthSource.Text -ne "自动测试") { throw "A/B 实际强度显示测试失败" }
  $script:FloatingMonitorWindow = New-FloatingMonitorWindow
  Update-FloatingMonitor
  if ($script:FloatingStrengthAValue.Text -ne "17" -or $script:FloatingStrengthBValue.Text -ne "23" -or $script:FloatingDurationValue.Text -ne "本次持续：2 秒" -or $script:FloatingRemainingValue.Text -ne "剩余时间：未输出") {
    throw "悬浮监控窗口内容测试失败"
  }
  $script:State.OutputActive = $true
  $script:State.OutputHoldUntilWhitelist = $false
  $script:State.OutputProfile = @{ DurationMs = 3000 }
  $script:State.OutputEnd = (Get-Date).AddSeconds(2.5)
  Update-FloatingMonitor
  if ($script:FloatingDurationValue.Text -ne "本次持续：3 秒" -or $script:FloatingRemainingValue.Text -notmatch '^剩余时间：[0-9]+\.[0-9] 秒$') {
    throw "悬浮监控单次持续或剩余时间测试失败"
  }
  $script:State.OutputActive = $false
  $script:State.OutputProfile = $null
  $script:State.OutputEnd = [DateTime]::MinValue
  $script:FloatingMonitorWindow.Close()
  $profileLimitTest = @{ AStrength = 90; BStrength = 70 }
  $script:State.DeviceMode = "http"
  $HttpLimitAInput.Text = "20"; $HttpLimitBInput.Text = "30"
  $profileLimitTest = Limit-TriggerProfile $profileLimitTest
  if ($profileLimitTest.AStrength -ne 20 -or $profileLimitTest.BStrength -ne 30) { throw "HTTP 手动上限截断失败" }
  $script:State.DeviceMode = "socket"
  $script:State.SocketHasAppLimits = $false
  $socketUnknownBlocked = $false
  try { Limit-TriggerProfile @{ AStrength = 10; BStrength = 10 } | Out-Null } catch { $socketUnknownBlocked = $true }
  if (-not $socketUnknownBlocked) { throw "Socket 未获 App 上限时没有禁止输出" }
  Set-SocketAppStrengthState 12 14 15 18
  $profileLimitTest = Limit-TriggerProfile @{ AStrength = 50; BStrength = 60 }
  if ($profileLimitTest.AStrength -ne 15 -or $profileLimitTest.BStrength -ne 18) { throw "Socket App 上限截断失败" }
  $script:SocketStopCalledByTimer = $false
  function Invoke-DeviceStop {
    $script:SocketStopCalledByTimer = $true
    $script:State.OutputActive = $false
    $script:State.OutputHoldUntilWhitelist = $false
    $script:State.OutputProfile = $null
    $script:State.OutputEnd = [DateTime]::MinValue
    $script:State.HoldRetriggerPending = $false
    $script:State.HoldCooldownEnd = [DateTime]::MinValue
    return $true
  }
  $script:State.DeviceMode = "socket"
  $script:State.OutputActive = $true
  $script:State.OutputHoldUntilWhitelist = $false
  $script:State.OutputEnd = (Get-Date).AddSeconds(-1)
  Update-OutputExpiration
  if (-not $script:SocketStopCalledByTimer) { throw "Socket 到期未调用停止流程" }
  $script:SocketStopCalledByTimer = $false
  $script:State.WindowState = "left"
  $script:State.OutputActive = $true
  $script:State.OutputHoldUntilWhitelist = $true
  $script:State.OutputProfile = @{ CooldownMs = 5000 }
  $script:State.OutputEnd = (Get-Date).AddSeconds(-1)
  Update-OutputExpiration
  if (-not $script:SocketStopCalledByTimer -or -not $script:State.HoldRetriggerPending) { throw "持续模式到期未停止或未进入冷却" }
  $script:HoldRetriggerTestCalled = $false
  function Invoke-Trigger($Reason) {
    if ($Reason -eq "冷却结束仍未返回白名单") { $script:HoldRetriggerTestCalled = $true; return $true }
    return $false
  }
  $script:State.Running = $true
  $script:State.Paused = $false
  $script:State.Locked = $false
  $script:State.Connected = $true
  $script:State.HoldCooldownEnd = (Get-Date).AddSeconds(-1)
  Update-HoldCooldown
  if (-not $script:HoldRetriggerTestCalled -or $script:State.HoldRetriggerPending) { throw "冷却结束后未按条件重新触发" }
  Write-Output "Desktop config, bounded hold/cooldown, and Socket expiration: OK"
  return
}
[void]$window.ShowDialog()










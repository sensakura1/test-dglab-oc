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
            string[] requestParts = requestLines.Length == 0 ? new string[0] : requestLines[0].Split(' ');
            string requestPath = requestParts.Length == 3 ? requestParts[1] : "";
            if (requestPath.IndexOf('?') >= 0 || requestPath.IndexOf('#') >= 0)
                throw new InvalidDataException("WebSocket registration path must not contain a query or fragment.");
            try { requestPath = Uri.UnescapeDataString(requestPath); }
            catch (UriFormatException) { throw new InvalidDataException("Invalid WebSocket registration path encoding."); }
            requestPath = requestPath.TrimEnd('/');
            string expectedPath = "/" + ClientId;
            bool acceptedPath = string.IsNullOrEmpty(requestPath) ||
                string.Equals(requestPath, expectedPath, StringComparison.OrdinalIgnoreCase);
            if (requestParts.Length != 3 || !string.Equals(requestParts[0], "GET", StringComparison.Ordinal) ||
                !string.Equals(requestParts[2], "HTTP/1.1", StringComparison.OrdinalIgnoreCase) ||
                !acceptedPath)
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
            LastError = "";

            lock (sync)
            {
                if (appClient != null) { try { appClient.Close(); } catch { } }
                appClient = client;
                appClient.SendTimeout = 1000;
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
        else if (type == "msg" && IsBound && clientId == ClientId && targetId == TargetId)
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


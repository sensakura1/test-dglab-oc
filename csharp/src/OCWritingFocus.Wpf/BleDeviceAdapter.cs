using OCWritingFocus.Core;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Storage.Streams;

namespace OCWritingFocus.Wpf;

internal sealed class BleDeviceAdapter(string address, SafetyConfig safety) : IDeviceAdapter
{
    private static readonly Guid ServiceUuid = Guid.Parse("0000180c-0000-1000-8000-00805f9b34fb");
    private static readonly Guid WriteUuid = Guid.Parse("0000150a-0000-1000-8000-00805f9b34fb");
    private BluetoothLEDevice? _device;
    private GattDeviceService? _service;
    private GattCharacteristic? _write;
    public DeviceStatus Status { get; private set; } = new(false, "蓝牙设备未连接", "未连接", LimitA: safety.SoftLimitA, LimitB: safety.SoftLimitB, HasLimits: true);

    public async Task ConnectAsync(CancellationToken cancellationToken)
    {
        var clean = address.Replace(":", "").Replace("-", "").Replace(" ", "");
        if (clean.Length != 12 || !ulong.TryParse(clean, System.Globalization.NumberStyles.HexNumber, null, out var numeric)) throw new InvalidOperationException("蓝牙模式需要 12 位十六进制蓝牙地址。 ");
        _device = await BluetoothLEDevice.FromBluetoothAddressAsync(numeric).AsTask(cancellationToken) ?? throw new InvalidOperationException("未找到指定蓝牙设备，请先在 Windows 中完成配对。 ");
        var services = await _device.GetGattServicesForUuidAsync(ServiceUuid, BluetoothCacheMode.Uncached).AsTask(cancellationToken);
        if (services.Status != GattCommunicationStatus.Success || services.Services.Count == 0) throw new InvalidOperationException("未找到 DG-LAB V3 服务。 ");
        _service = services.Services[0];
        var characteristics = await _service.GetCharacteristicsForUuidAsync(WriteUuid, BluetoothCacheMode.Uncached).AsTask(cancellationToken);
        if (characteristics.Status != GattCommunicationStatus.Success || characteristics.Characteristics.Count == 0) throw new InvalidOperationException("未找到 DG-LAB V3 写入特征。 ");
        _write = characteristics.Characteristics[0];
        Status = Status with { Connected = true, Text = "蓝牙设备已连接", Source = "蓝牙 V3 直连" };
        await WriteAsync(DgLabPackets.Safety(safety), cancellationToken);
    }

    public async Task ApplySafetyAsync(CancellationToken cancellationToken) => await WriteAsync(DgLabPackets.Safety(safety), cancellationToken);

    public async Task ActivateAsync(OutputProfile profile, CancellationToken cancellationToken)
    {
        var limited = profile with { StrengthA = Math.Min(profile.StrengthA, safety.SoftLimitA), StrengthB = Math.Min(profile.StrengthB, safety.SoftLimitB) };
        await WriteAsync(DgLabPackets.Output(limited), cancellationToken);
        Status = Status with { ActualA = limited.StrengthA, ActualB = limited.StrengthB, Known = true, Source = "蓝牙已确认下发" };
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        if (_write is null) return;
        await WriteAsync(DgLabPackets.Output(new OutputProfile(0, 0, "both", TimeSpan.Zero, TimeSpan.Zero, false, true, "constant", 100, 0), true), cancellationToken);
        Status = Status with { ActualA = 0, ActualB = 0, Known = true, Source = "蓝牙已确认下发" };
    }

    public async Task DisconnectAsync(CancellationToken cancellationToken)
    {
        try { await StopAsync(cancellationToken); } catch { }
        _write = null; _service?.Dispose(); _service = null; _device?.Dispose(); _device = null;
        Status = Status with { Connected = false, Known = false, Text = "蓝牙设备未连接", Source = "设备已断开" };
    }

    public async ValueTask DisposeAsync() => await DisconnectAsync(CancellationToken.None);

    private async Task WriteAsync(byte[] data, CancellationToken cancellationToken)
    {
        if (_write is null || !Status.Connected) throw new InvalidOperationException("蓝牙写入特征未连接。 ");
        using var writer = new DataWriter(); writer.WriteBytes(data); var buffer = writer.DetachBuffer();
        var result = await _write.WriteValueWithResultAsync(buffer, GattWriteOption.WriteWithoutResponse).AsTask(cancellationToken);
        if (result.Status != GattCommunicationStatus.Success) throw new InvalidOperationException($"蓝牙写入失败：{result.Status}");
    }
}

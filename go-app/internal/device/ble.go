package device

import (
	"context"
	"encoding/hex"
	"fmt"
	"strings"
	"sync"

	"tinygo.org/x/bluetooth"

	appconfig "ocwritingfocus/goapp/internal/config"
)

var (
	dglabServiceUUID, _ = bluetooth.ParseUUID("0000180c-0000-1000-8000-00805f9b34fb")
	dglabWriteUUID, _   = bluetooth.ParseUUID("0000150a-0000-1000-8000-00805f9b34fb")
)

type BLEAdapter struct {
	mu      sync.Mutex
	Address string
	Safety  appconfig.SafetyConfig
	device  bluetooth.Device
	write   bluetooth.DeviceCharacteristic
	status  Status
}

func NewBLE(address string, safety appconfig.SafetyConfig) *BLEAdapter {
	return &BLEAdapter{
		Address: address, Safety: safety,
		status: Status{Text: "蓝牙设备未连接", Source: "未连接", LimitA: safety.SoftLimitA, LimitB: safety.SoftLimitB, HasLimits: true},
	}
}

func (a *BLEAdapter) Connect(ctx context.Context) error {
	clean := strings.NewReplacer(":", "", "-", "", " ", "").Replace(a.Address)
	if len(clean) != 12 {
		return fmt.Errorf("蓝牙模式需要 12 位十六进制蓝牙地址")
	}
	bytes, err := hex.DecodeString(clean)
	if err != nil {
		return fmt.Errorf("蓝牙地址无效: %w", err)
	}
	address := bluetooth.Address{MACAddress: bluetooth.MACAddress{MAC: bluetooth.MAC{bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5]}}}
	adapter := bluetooth.DefaultAdapter
	if err := adapter.Enable(); err != nil {
		return err
	}
	device, err := adapter.Connect(address, bluetooth.ConnectionParams{})
	if err != nil {
		return err
	}
	services, err := device.DiscoverServices([]bluetooth.UUID{dglabServiceUUID})
	if err != nil || len(services) == 0 {
		_ = device.Disconnect()
		return fmt.Errorf("未找到 DG-LAB V3 服务: %w", err)
	}
	characteristics, err := services[0].DiscoverCharacteristics([]bluetooth.UUID{dglabWriteUUID})
	if err != nil || len(characteristics) == 0 {
		_ = device.Disconnect()
		return fmt.Errorf("未找到 DG-LAB V3 写入特征: %w", err)
	}
	a.mu.Lock()
	a.device = device
	a.write = characteristics[0]
	a.status.Connected = true
	a.status.Text = "蓝牙设备已连接"
	a.status.Source = "蓝牙 V3 直连"
	a.mu.Unlock()
	if err := a.ApplySafety(ctx); err != nil {
		_ = a.Disconnect(ctx)
		return err
	}
	return nil
}

func (a *BLEAdapter) ApplySafety(ctx context.Context) error {
	return a.writeBytes([]byte{
		0xBF,
		byte(a.Safety.SoftLimitA), byte(a.Safety.SoftLimitB),
		byte(a.Safety.FrequencyBalanceA), byte(a.Safety.FrequencyBalanceB),
		byte(a.Safety.StrengthBalanceA), byte(a.Safety.StrengthBalanceB),
	})
}

func (a *BLEAdapter) Activate(ctx context.Context, profile Profile) error {
	profile = Limit(profile, a.Safety.SoftLimitA, a.Safety.SoftLimitB)
	if err := a.writeBytes(b0Packet(profile, false)); err != nil {
		return err
	}
	a.mu.Lock()
	a.status.ActualA, a.status.ActualB, a.status.Known = profile.AStrength, profile.BStrength, true
	a.status.Source = "蓝牙已确认下发"
	a.mu.Unlock()
	return nil
}

func (a *BLEAdapter) Stop(ctx context.Context) error {
	err := a.writeBytes(b0Packet(Profile{}, true))
	if err == nil {
		a.mu.Lock()
		a.status.ActualA, a.status.ActualB, a.status.Known = 0, 0, true
		a.status.Source = "蓝牙已确认下发"
		a.mu.Unlock()
	}
	return err
}

func (a *BLEAdapter) Disconnect(ctx context.Context) error {
	a.mu.Lock()
	device := a.device
	a.status.Connected = false
	a.status.Known = false
	a.status.Text = "蓝牙设备未连接"
	a.status.Source = "设备已断开"
	a.mu.Unlock()
	return device.Disconnect()
}

func (a *BLEAdapter) Status() Status {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.status
}

func (a *BLEAdapter) writeBytes(data []byte) error {
	a.mu.Lock()
	characteristic := a.write
	connected := a.status.Connected
	a.mu.Unlock()
	if !connected {
		return fmt.Errorf("蓝牙写入特征未连接")
	}
	_, err := characteristic.WriteWithoutResponse(data)
	return err
}

func b0Packet(profile Profile, stop bool) []byte {
	parseMode := byte(0x0F)
	strengthA, strengthB := byte(0), byte(0)
	frequencyA, intensityA := waveform(profile)
	frequencyB, intensityB := frequencyA, intensityA
	if !stop {
		parseMode = 0
		if profile.AEnabled {
			parseMode |= 0x0C
			strengthA = byte(profile.AStrength)
		} else {
			intensityA = [4]byte{101, 101, 101, 101}
		}
		if profile.BEnabled {
			parseMode |= 0x03
			strengthB = byte(profile.BStrength)
		} else {
			intensityB = [4]byte{101, 101, 101, 101}
		}
	} else {
		frequencyA, frequencyB = [4]byte{10, 10, 10, 10}, [4]byte{10, 10, 10, 10}
		intensityA, intensityB = [4]byte{}, [4]byte{}
	}
	return []byte{
		0xB0, parseMode, strengthA, strengthB,
		frequencyA[0], frequencyA[1], frequencyA[2], frequencyA[3],
		intensityA[0], intensityA[1], intensityA[2], intensityA[3],
		frequencyB[0], frequencyB[1], frequencyB[2], frequencyB[3],
		intensityB[0], intensityB[1], intensityB[2], intensityB[3],
	}
}

func waveform(profile Profile) ([4]byte, [4]byte) {
	frequency := byte(max(10, min(100, profile.WavePeriodMs/10)))
	level := byte(max(0, min(100, profile.WaveIntensity)))
	frequencies := [4]byte{frequency, frequency, frequency, frequency}
	levels := [4]byte{level, level, level, level}
	switch profile.Waveform {
	case "pulse":
		levels = [4]byte{level, 0, level, 0}
	case "ramp":
		levels = [4]byte{byte(float64(level) * .25), byte(float64(level) * .5), byte(float64(level) * .75), level}
	case "heartbeat":
		levels = [4]byte{level, byte(float64(level) * .35), 0, byte(float64(level) * .7)}
	}
	return frequencies, levels
}

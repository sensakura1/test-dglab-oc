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


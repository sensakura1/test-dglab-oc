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


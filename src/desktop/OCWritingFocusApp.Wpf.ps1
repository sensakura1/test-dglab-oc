Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

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
             <Border Background="#25384A" CornerRadius="3" Padding="10,5" Margin="0,0,8,0">
              <TextBlock x:Name="DeviceBadge" Text="HTTP 桥接" Foreground="#66B3FF" FontWeight="Bold"/>
            </Border>
             <Border x:Name="LockBadgeBorder" Background="#25384A" CornerRadius="3" Padding="10,5" Margin="0,0,8,0">
              <TextBlock x:Name="LockBadge" Text="未锁定" Foreground="#66B3FF" FontWeight="Bold"/>
            </Border>
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
                  <TextBlock Text="固定持续时间 ms" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="DurationInput" Text="5000"/>
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
                  <TextBlock Text="V3 设备、安全上限与平衡参数" FontSize="18" FontWeight="Bold"/>
                  <TextBlock Text="BF 参数会在每次蓝牙重连后重新写入；设备会断电保存，修改前请确认安全范围。" Foreground="{StaticResource Muted}" Margin="0,4,0,0"/>
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
              <Grid Margin="0,14,0,12">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="1.05*"/>
                  <ColumnDefinition Width="1.7*"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <StackPanel Margin="0,0,8,10">
                  <TextBlock Text="连接模式" Foreground="{StaticResource Muted}"/>
                  <ComboBox x:Name="DeviceModeCombo" SelectedIndex="0">
                    <ComboBoxItem Content="HTTP 真实设备桥接"/>
                    <ComboBoxItem Content="蓝牙 V3 直连"/>
                  </ComboBox>
                </StackPanel>
                <StackPanel Grid.Column="1" Margin="0,0,8,10">
                  <TextBlock Text="接口地址 / 12 位蓝牙地址" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="EndpointInput" Text="http://127.0.0.1:8080"/>
                </StackPanel>
                <StackPanel Grid.Column="2" Margin="0,0,8,10">
                  <TextBlock Text="A 软上限（0–200）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="SoftLimitAInput" Text="80"/>
                </StackPanel>
                <StackPanel Grid.Column="3" Margin="0,0,0,10">
                  <TextBlock Text="B 软上限（0–200）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="SoftLimitBInput" Text="80"/>
                </StackPanel>
                <StackPanel Grid.Row="1" Margin="0,0,8,0">
                  <TextBlock Text="A 频率平衡（0–255）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="FrequencyBalanceAInput" Text="0"/>
                </StackPanel>
                <StackPanel Grid.Row="1" Grid.Column="1" Margin="0,0,8,0">
                  <TextBlock Text="B 频率平衡（0–255）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="FrequencyBalanceBInput" Text="0"/>
                </StackPanel>
                <StackPanel Grid.Row="1" Grid.Column="2" Margin="0,0,8,0">
                  <TextBlock Text="A 脉宽平衡（0–255）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="StrengthBalanceAInput" Text="0"/>
                </StackPanel>
                <StackPanel Grid.Row="1" Grid.Column="3">
                  <TextBlock Text="B 脉宽平衡（0–255）" Foreground="{StaticResource Muted}"/>
                  <TextBox x:Name="StrengthBalanceBInput" Text="0"/>
                </StackPanel>
              </Grid>
              <WrapPanel>
                <Button x:Name="ConnectButton" Style="{StaticResource PrimaryButton}" Content="连接并应用安全参数" Width="170" Margin="0,0,8,0"/>
                <Button x:Name="ApplySafetyButton" Style="{StaticResource SecondaryButton}" Content="重新应用 BF 参数" Width="145" Margin="0,0,8,0"/>
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
$LockBadge = Find-Control "LockBadge"
$LockBadgeBorder = Find-Control "LockBadgeBorder"
$DeviceModeCombo = Find-Control "DeviceModeCombo"
$EndpointInput = Find-Control "EndpointInput"
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
$ConnectButton = Find-Control "ConnectButton"
$ApplySafetyButton = Find-Control "ApplySafetyButton"
$DisconnectButton = Find-Control "DisconnectButton"
$StopButton = Find-Control "StopButton"
$ClearLogsButton = Find-Control "ClearLogsButton"

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
  HttpRenewAt = [DateTime]::MinValue
}

function Get-IntText($TextBox, [int]$Default) {
  $value = 0
  if ([int]::TryParse($TextBox.Text, [ref]$value)) { return $value }
  return $Default
}

function Format-Seconds([int]$Seconds) {
  if ($Seconds -lt 0) { $Seconds = 0 }
  return "{0:00}:{1:00}" -f [Math]::Floor($Seconds / 60), ($Seconds % 60)
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
  if ($script:State.DeviceMode -eq "http") {
    $DeviceValue.Text = if ($script:State.Connected) { "真实桥接已连接" } else { "真实桥接未连接" }
    $DeviceBadge.Text = if ($script:State.Connected) { "真实设备桥接" } else { "真实桥接未连接" }
  } elseif ($script:State.DeviceMode -eq "ble") {
    $DeviceValue.Text = if ($script:State.Connected) { "蓝牙设备已连接" } else { "蓝牙设备未连接" }
    $DeviceBadge.Text = if ($script:State.Connected) { "蓝牙 V3 直连" } else { "蓝牙未连接" }
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
    DurationMs = Get-ClampedInt $DurationInput 5000 100 30000
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
    $address = Convert-BleAddress $EndpointInput.Text
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
      $endAt = [DateTime]::MaxValue
    } elseif ($script:Ble.OutputActive -and -not $Profile.RestartOnRepeat -and $script:Ble.OutputEnd -gt $now) {
      $endAt = $script:Ble.OutputEnd.AddMilliseconds($Profile.DurationMs)
    } else {
      $endAt = $now.AddMilliseconds($Profile.DurationMs)
    }
    Invoke-BleWrite (New-DglabB0Packet $Profile)
    $script:Ble.OutputProfile = $Profile
    $script:Ble.OutputEnd = $endAt
    $script:Ble.OutputActive = $true
    return $true
  } catch {
    Add-Log "蓝牙触发失败：$($_.Exception.Message)"
    return $false
  }
}

function Get-EndpointUrl($Action) {
  $base = $EndpointInput.Text.Trim().TrimEnd("/")
  if ([string]::IsNullOrWhiteSpace($base)) {
    throw "接口地址不能为空"
  }
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
  $script:State.HttpRenewAt = [DateTime]::MinValue
  if ($script:State.DeviceMode -eq "ble") {
    return Invoke-BleStop
  }

  try {
    $url = Get-EndpointUrl "stop"
    $body = @{ action = "stop" } | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body $body -TimeoutSec 5 | Out-Null
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
    $duration = if ($Profile.HoldUntilWhitelist) { 30000 } else { $Profile.DurationMs }
    $safety = Get-BleSafetyConfig
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
      softLimitA = $safety.SoftLimitA
      softLimitB = $safety.SoftLimitB
    } | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body $body -TimeoutSec 5 | Out-Null
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
  if ($Reason -notin @("黑名单直接触发", "离开写作范围")) {
    $profile.HoldUntilWhitelist = $false
  }
  $sent = Invoke-DeviceActivate $profile
  if (-not $sent) {
    return $false
  }

  $script:State.OutputActive = $true
  $script:State.OutputHoldUntilWhitelist = $profile.HoldUntilWhitelist
  $script:State.OutputProfile = $profile
  $script:State.OutputEnd = if ($profile.HoldUntilWhitelist) { [DateTime]::MaxValue } else { (Get-Date).AddMilliseconds($profile.DurationMs) }
  if ($script:State.DeviceMode -eq "http" -and $profile.HoldUntilWhitelist) {
    $script:State.HttpRenewAt = (Get-Date).AddSeconds(25)
  }

  $prefix = if ($script:State.DeviceMode -eq "ble") { "蓝牙输出" } else { "HTTP 输出" }
  $durationText = if ($profile.HoldUntilWhitelist) { "返回白名单时停止" } else { "$($profile.DurationMs)ms" }
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
$DeviceModeCombo.Add_SelectionChanged({
  if ($script:State.OutputActive -and $script:State.Connected) { Invoke-DeviceStop | Out-Null }
  if ($DeviceModeCombo.SelectedIndex -eq 1) {
    $script:State.DeviceMode = "ble"
    $script:State.Connected = $false
    $EndpointInput.Text = "输入 12 位十六进制蓝牙地址"
    Add-Log "已切换到蓝牙 V3 直连模式"
  } else {
    $script:State.DeviceMode = "http"
    $script:State.Connected = $false
    if ($EndpointInput.Text -match "47L|^[0-9A-Fa-f: -]{12,}$") {
      $EndpointInput.Text = "http://127.0.0.1:8080"
    }
    Add-Log "已切换到 HTTP 真实设备桥接模式"
  }
  Update-View
})
$ConnectButton.Add_Click({ Invoke-DeviceStatus; Update-View })
$ApplySafetyButton.Add_Click({ Apply-BleSafetySettings | Out-Null; Update-View })
$DisconnectButton.Add_Click({
  if ($script:State.Connected) { Invoke-DeviceStop | Out-Null }
  $script:State.Connected = $false
  $script:Ble.WriteCharacteristic = $null
  $script:Ble.Service = $null
  $script:Ble.Device = $null
  Add-Log "设备连接已断开"
  Update-View
})
$StopButton.Add_Click({ Invoke-DeviceStop; Update-View })
$ClearLogsButton.Add_Click({ $LogList.Items.Clear() })

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

$bleOutputTimer = New-Object Windows.Threading.DispatcherTimer
$bleOutputTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$bleOutputTimer.Add_Tick({
  if (-not $script:Ble.OutputActive) { return }
  if (-not $script:State.Connected -or $script:State.Locked -or (Get-Date) -ge $script:Ble.OutputEnd) {
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

  if ($script:State.OutputActive -and $script:State.OutputHoldUntilWhitelist -and $script:State.DeviceMode -eq "http" -and $script:State.Connected -and (Get-Date) -ge $script:State.HttpRenewAt) {
    if (Invoke-HttpActivate $script:State.OutputProfile) {
      $script:State.HttpRenewAt = (Get-Date).AddSeconds(25)
    } else {
      $script:State.OutputActive = $false
    }
  }
  if ($script:State.OutputActive -and -not $script:State.OutputHoldUntilWhitelist -and $script:State.DeviceMode -eq "http" -and (Get-Date) -ge $script:State.OutputEnd) {
    $script:State.OutputActive = $false
    $script:State.OutputProfile = $null
  }
  Update-View
})

$window.Add_Closing({
  $timer.Stop()
  $bleOutputTimer.Stop()
  if ($script:State.Connected) {
    Invoke-DeviceStop | Out-Null
  }
})

$timer.Start()
Initialize-ScopeLists
Show-AppPage "dashboard"
Refresh-CurrentWindow | Out-Null
Refresh-WindowPicker
Add-Log "桌面应用已启动"
Update-View
[void]$window.ShowDialog()










#Requires -Version 5.1
<#
.SYNOPSIS
    OphiStreamer Milestone 0 - test launcher window (SteamOS-style).

.DESCRIPTION
    Same steps as m0-start.ps1, in a window: joins the phone hotspot, sets up the
    firewall and network pinning (one admin prompt, only when needed), runs the
    hardware test as a normal user and shows each result live. The Moonlight
    question is answered with buttons.

    Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
#>
[CmdletBinding()]
param(
    # Developer check: build the window, save a PNG of it, and exit.
    [string]$Screenshot
)

$ErrorActionPreference = 'Stop'

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$here = $PSScriptRoot
. (Join-Path $here 'm0-lib.ps1')

# ---------------------------------------------------------------- steps shown in the window

$Steps = [ordered]@{
    join      = @('Join phone hotspot', 'Connects the laptop to the phone')
    firewall  = @('Firewall and pinning', 'One admin prompt, first time only')
    link      = @('Hotspot link', '5 GHz, signal, phone reachable')
    lagfix    = @('Lag fix', 'Works without admin, undone on exit and crash')
    latency   = @('Latency', 'Without vs. with the lag fix')
    stable    = @('Connection log', 'Every second: drops, signal, channel, ping')
    moonlight = @('Moonlight stream', 'You confirm a real stream')
}

# Which test result lines belong to which step.
$StepOf = @{
    'Wi-Fi adapter present'          = 'link'
    'WLAN AutoConfig service'        = 'link'
    'Laptop joined phone hotspot'    = 'link'
    'Link on 5 GHz'                  = 'link'
    'Signal'                         = 'link'
    'Phone network pinned'           = 'link'
    'Phone answers on the hotspot'   = 'link'
    'Hotspot capability'             = 'link'
    'Start hotspot without admin'    = 'link'
    'Start hotspot on 5 GHz'         = 'link'
    '5 GHz band'                     = 'link'
    'Phone connects'                 = 'link'
    'Open WLAN handle'               = 'lagfix'
    'Lag fix works without admin'    = 'lagfix'
    'Lag fix undone when app closes' = 'lagfix'
    'Lag fix undone when app crashes' = 'lagfix'
    'Lag spikes reduced'             = 'latency'
    'Moonlight streams over hotspot' = 'moonlight'
    'Connection stayed up'           = 'stable'
}

$SectionStep = @{ '2' = 'link'; '3' = 'lagfix'; '5' = 'latency'; '6' = 'moonlight' }

$Colors = @{
    WAITING = '#8B98A5'; RUNNING = '#1A9FFF'; PASS = '#59BF40'; WARN = '#E6B450'
    FAIL = '#E5534B'; SKIP = '#8B98A5'; INFO = '#5B6773'
}
$Rank = @{ WAITING = 0; RUNNING = 1; SKIP = 2; PASS = 3; WARN = 4; FAIL = 5 }

$stepRows = foreach ($id in $Steps.Keys) {
    @"
        <Border BorderBrush="#212B37" BorderThickness="0,0,0,1" Padding="16,12">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel>
              <TextBlock Text="$($Steps[$id][0])" FontSize="14"/>
              <TextBlock x:Name="Sub_$id" Text="$($Steps[$id][1])" FontSize="12" Foreground="#8B98A5" TextWrapping="Wrap" Margin="0,2,12,0"/>
            </StackPanel>
            <Border x:Name="Pill_$id" Grid.Column="1" CornerRadius="10" Padding="10,3" Background="#1F2833" VerticalAlignment="Center">
              <TextBlock x:Name="PillText_$id" Text="WAITING" FontSize="10" FontWeight="Bold" Foreground="#8B98A5"/>
            </Border>
          </Grid>
        </Border>
"@
}

# ---------------------------------------------------------------- window

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OphiStreamer Test Kit" Width="560" Height="800" MinHeight="600"
        WindowStyle="None" ResizeMode="CanResizeWithGrip" WindowStartupLocation="CenterScreen"
        Background="#0B0F14" Foreground="#DCDEDF" FontFamily="Segoe UI Variable Text, Segoe UI">
  <Window.Resources>
    <Style x:Key="Caption" TargetType="TextBlock">
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#8B98A5"/>
      <Setter Property="Margin" Value="4,18,0,8"/>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="#151C25"/>
      <Setter Property="BorderBrush" Value="#26313E"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="6"/>
    </Style>
    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Height" Value="48"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="4" BorderBrush="White" BorderThickness="0">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                  <GradientStop Color="#1A9FFF" Offset="0"/><GradientStop Color="#0B6FD1" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderThickness" Value="2"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Secondary" TargetType="Button">
      <Setter Property="Foreground" Value="#DCDEDF"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Height" Value="48"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="4" Background="#1F2833" BorderBrush="#26313E" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#26313E"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#1A9FFF"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Chrome" TargetType="Button">
      <Setter Property="Foreground" Value="#8B98A5"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="Width" Value="46"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="Transparent">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#26313E"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Seg" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#8B98A5"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="b" CornerRadius="4" Background="Transparent" Padding="14,7">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="#1A9FFF"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#0F151D"/>
      <Setter Property="Foreground" Value="#DCDEDF"/>
      <Setter Property="BorderBrush" Value="#26313E"/>
      <Setter Property="CaretBrush" Value="#DCDEDF"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="FontSize" Value="13"/>
    </Style>
    <Style TargetType="PasswordBox">
      <Setter Property="Background" Value="#0F151D"/>
      <Setter Property="Foreground" Value="#DCDEDF"/>
      <Setter Property="BorderBrush" Value="#26313E"/>
      <Setter Property="CaretBrush" Value="#DCDEDF"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="FontSize" Value="13"/>
    </Style>
  </Window.Resources>

  <Border BorderBrush="#26313E" BorderThickness="1">
    <Grid>
      <Grid.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#1B2838" Offset="0"/><GradientStop Color="#0B0F14" Offset="0.55"/>
        </LinearGradientBrush>
      </Grid.Background>
      <Grid.RowDefinitions>
        <RowDefinition Height="36"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Grid x:Name="TitleBar" Background="#0E141B">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="14,0">
          <TextBlock Text="&#xE701;" FontFamily="Segoe MDL2 Assets" Foreground="#1A9FFF" FontSize="14" VerticalAlignment="Center"/>
          <TextBlock Text="OphiStreamer Test Kit" Foreground="#8B98A5" FontSize="12" Margin="10,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="MinBtn" Style="{StaticResource Chrome}" Content="&#xE921;"/>
          <Button x:Name="CloseBtn" Style="{StaticResource Chrome}" Content="&#xE8BB;"/>
        </StackPanel>
      </Grid>

      <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Hidden">
        <StackPanel Margin="20,16,20,8">
          <TextBlock Text="OPHISTREAMER" Foreground="#1A9FFF" FontSize="11" FontWeight="Bold"/>
          <TextBlock Text="Test Kit" FontSize="26" FontWeight="SemiBold"/>

          <Border CornerRadius="6" BorderBrush="#26313E" BorderThickness="1" Padding="18" Margin="0,14,0,0">
            <Border.Background>
              <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                <GradientStop Color="#2A475E" Offset="0"/><GradientStop Color="#151C25" Offset="1"/>
              </LinearGradientBrush>
            </Border.Background>
            <StackPanel>
              <TextBlock x:Name="HeroTitle" Text="Ready to test" FontSize="20" FontWeight="SemiBold"/>
              <TextBlock x:Name="HeroSub" Text="Turn the phone hotspot on, then press Start test." Foreground="#8B98A5" FontSize="13" TextWrapping="Wrap" Margin="0,2,0,0"/>
              <ProgressBar x:Name="Progress" Height="4" Margin="0,14,0,0" Foreground="#1A9FFF" Background="#26313E" BorderThickness="0" Value="0"/>
            </StackPanel>
          </Border>

          <TextBlock Style="{StaticResource Caption}" Text="SETUP"/>
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <Border BorderBrush="#212B37" BorderThickness="0,0,0,1" Padding="16,12">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <TextBlock Text="Mode" FontSize="14" VerticalAlignment="Center"/>
                  <Border Grid.Column="1" Background="#0F151D" CornerRadius="5" Padding="3">
                    <StackPanel Orientation="Horizontal">
                      <RadioButton x:Name="ModePhone" GroupName="mode" Style="{StaticResource Seg}" Content="Phone hotspot" IsChecked="True"/>
                      <RadioButton x:Name="ModeLaptop" GroupName="mode" Style="{StaticResource Seg}" Content="Laptop hotspot"/>
                    </StackPanel>
                  </Border>
                </Grid>
              </Border>
              <Border x:Name="SsidRow" BorderBrush="#212B37" BorderThickness="0,0,0,1" Padding="16,12">
                <StackPanel>
                  <TextBlock Text="Phone hotspot name" FontSize="14"/>
                  <TextBlock Text="As shown on the phone. Filled in if the laptop is already on it." Foreground="#8B98A5" FontSize="12" Margin="0,2,0,8"/>
                  <TextBox x:Name="SsidBox"/>
                </StackPanel>
              </Border>
              <Border x:Name="PwRow" BorderBrush="#212B37" BorderThickness="0,0,0,1" Padding="16,12">
                <StackPanel>
                  <TextBlock Text="Hotspot password" FontSize="14"/>
                  <TextBlock Text="Only needed the first time; Windows remembers it." Foreground="#8B98A5" FontSize="12" Margin="0,2,0,8"/>
                  <PasswordBox x:Name="PwBox"/>
                </StackPanel>
              </Border>
              <Border BorderBrush="#212B37" BorderThickness="0,0,0,1" Padding="16,12">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center">
                    <TextBlock Text="Latency phases" FontSize="14"/>
                    <TextBlock Text="Longer catches more spikes" Foreground="#8B98A5" FontSize="12"/>
                  </StackPanel>
                  <Border Grid.Column="1" Background="#0F151D" CornerRadius="5" Padding="3" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal">
                      <RadioButton x:Name="Dur90" GroupName="dur" Style="{StaticResource Seg}" Content="90 s" IsChecked="True"/>
                      <RadioButton x:Name="Dur180" GroupName="dur" Style="{StaticResource Seg}" Content="180 s"/>
                    </StackPanel>
                  </Border>
                </Grid>
              </Border>
              <TextBlock Margin="16,12" Foreground="#8B98A5" FontSize="12" TextWrapping="Wrap"
                         Text="Phone: Personal hotspot &gt; More &gt; AP band = 5 GHz (once), then turn the hotspot on. Plug the laptop in and start Sunshine."/>
            </StackPanel>
          </Border>

          <Border x:Name="AskPanel" Visibility="Collapsed" Background="#151C25" BorderBrush="#1A9FFF" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,18,0,0">
            <StackPanel>
              <TextBlock Text="Stream with Moonlight now" FontSize="16" FontWeight="SemiBold"/>
              <TextBlock x:Name="AskText" Foreground="#8B98A5" FontSize="13" TextWrapping="Wrap" Margin="0,4,0,10"/>
              <TextBlock Text="Notes (optional): stutter, quality, errors" Foreground="#8B98A5" FontSize="12" Margin="0,0,0,6"/>
              <TextBox x:Name="NotesBox"/>
              <Grid Margin="0,12,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="2*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Button x:Name="AskYes" Style="{StaticResource Primary}" Content="IT STREAMED"/>
                <Button x:Name="AskNo" Grid.Column="2" Style="{StaticResource Secondary}" Content="It didn't"/>
                <Button x:Name="AskSkip" Grid.Column="4" Style="{StaticResource Secondary}" Content="Skip"/>
              </Grid>
            </StackPanel>
          </Border>

          <TextBlock Style="{StaticResource Caption}" Text="STEPS"/>
          <Border Style="{StaticResource Card}">
            <StackPanel>
$($stepRows -join "`n")
            </StackPanel>
          </Border>

          <TextBlock Style="{StaticResource Caption}" Text="LIVE LOG"/>
          <Border Style="{StaticResource Card}" Height="190" Padding="12,8">
            <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Hidden">
              <StackPanel x:Name="LogPanel"/>
            </ScrollViewer>
          </Border>
        </StackPanel>
      </ScrollViewer>

      <Grid Grid.Row="2" Margin="20,12,20,18">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="10"/><ColumnDefinition Width="1.6*"/></Grid.ColumnDefinitions>
        <Button x:Name="OpenReport" Style="{StaticResource Secondary}" Content="Open report" IsEnabled="False"/>
        <Button x:Name="StartBtn" Grid.Column="2" Style="{StaticResource Primary}" Content="START TEST"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@

$window = [Windows.Markup.XamlReader]::Parse($xaml)
$ui = @{}
foreach ($n in 'TitleBar', 'MinBtn', 'CloseBtn', 'HeroTitle', 'HeroSub', 'Progress', 'ModePhone', 'ModeLaptop',
               'SsidRow', 'PwRow', 'SsidBox', 'PwBox', 'Dur90', 'Dur180', 'AskPanel', 'AskText', 'NotesBox',
               'AskYes', 'AskNo', 'AskSkip', 'LogPanel', 'LogScroll', 'OpenReport', 'StartBtn') {
    $ui[$n] = $window.FindName($n)
}
foreach ($id in $Steps.Keys) {
    foreach ($part in 'Sub', 'Pill', 'PillText') { $ui["${part}_$id"] = $window.FindName("${part}_$id") }
}

# ---------------------------------------------------------------- UI helpers

$brushes = New-Object Windows.Media.BrushConverter
function Get-Brush([string]$Hex) { $brushes.ConvertFromString($Hex) }

$script:StepState = @{}
$script:ReportPath = $null
$script:AnswerDir = $null
$script:Running = $false

function Set-Step([string]$Id, [string]$State, [string]$Sub) {
    $color = $Colors[$State]
    $ui["PillText_$Id"].Text = $State
    $ui["PillText_$Id"].Foreground = Get-Brush $color
    $ui["Pill_$Id"].Background = Get-Brush ('#2A' + $color.Substring(1))
    if ($Sub) { $ui["Sub_$Id"].Text = $Sub }
    $script:StepState[$Id] = $State
}

# Test results only ever make a step look worse, never better (one FAIL keeps it red).
function Update-Step([string]$Id, [string]$State, [string]$Sub) {
    $current = $script:StepState[$Id]
    if ($current -in 'WAITING', 'RUNNING' -or $Rank[$State] -ge $Rank[$current]) { Set-Step $Id $State $Sub }
}

function Add-Log([string]$Text, [string]$Color = '#8B98A5') {
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.Foreground = Get-Brush $Color
    $tb.TextWrapping = 'Wrap'
    $tb.FontFamily = New-Object Windows.Media.FontFamily 'Cascadia Mono, Consolas'
    $tb.FontSize = 11.5
    $tb.Margin = New-Object Windows.Thickness 0, 1, 0, 1
    [void]$ui.LogPanel.Children.Add($tb)
    $ui.LogScroll.ScrollToEnd()
}

function Set-Inputs([bool]$Enabled) {
    foreach ($n in 'ModePhone', 'ModeLaptop', 'SsidBox', 'PwBox', 'Dur90', 'Dur180', 'StartBtn') { $ui[$n].IsEnabled = $Enabled }
}

function Handle-Line([string]$Line) {
    if ($Line -match '^@@ASK moonlight\|([^|]*)\|(.*)$') {
        $ui.AskText.Text = "Lag fix is $($Matches[2]). On the phone: Moonlight, tap +, add $($Matches[1]). Pair, play for a minute or two, then answer here."
        $ui.AskPanel.Visibility = 'Visible'
        $ui.AskPanel.BringIntoView()
        Set-Step 'moonlight' 'RUNNING' 'Waiting for your answer'
        $ui.HeroSub.Text = 'Try a real stream with Moonlight, then answer below.'
        return
    }
    if ($Line -match '^Report saved: (.+)$') {
        $script:ReportPath = $Matches[1].Trim()
        Add-Log $Line '#DCDEDF'
        return
    }
    if ($Line -match '^Phase (A|B): (.*)$') {
        $ui.HeroSub.Text = "Latency phase $($Matches[1]): $($Matches[2])"
        Set-Step 'latency' 'RUNNING' $(if ($Matches[1] -eq 'A') { 'Phase A: normal Windows behaviour' } else { 'Phase B: lag fix on' })
        Add-Log $Line '#DCDEDF'
        return
    }
    if ($Line -match '^=== (\d)\. (.+) ===$') {
        $ui.HeroSub.Text = $Matches[2]
        $id = $SectionStep[$Matches[1]]
        if ($id -and $script:StepState[$id] -eq 'WAITING') { Set-Step $id 'RUNNING' }
        return
    }
    if ($Line -match '^\[(PASS|FAIL|WARN|SKIP|INFO)\] (.+?)(?: - (.*))?$') {
        $level = $Matches[1]
        $name = $Matches[2]
        $detail = $Matches[3]
        Add-Log $Line $Colors[$level]
        $id = $StepOf[$name]
        if ($id -and $level -ne 'INFO') { Update-Step $id $level $(if ($detail) { $detail } else { $name }) }
        if ($name -eq 'Connection log' -and $level -eq 'INFO') { Set-Step 'stable' 'RUNNING' $detail }
    }
}

function Complete-Run {
    $script:Running = $false
    Set-Inputs $true
    $ui.Progress.IsIndeterminate = $false
    $ui.Progress.Value = 100
    $ui.AskPanel.Visibility = 'Collapsed'
    foreach ($id in $Steps.Keys) {
        if ($script:StepState[$id] -in 'WAITING', 'RUNNING') { Set-Step $id 'SKIP' }
    }
    $states = $script:StepState.Values
    if ($states -contains 'FAIL') {
        $ui.HeroTitle.Text = 'Needs attention'
        $ui.HeroSub.Text = 'Red steps show what to fix. Send the report back to Claude.'
    } elseif ($states -contains 'WARN') {
        $ui.HeroTitle.Text = 'Done, with warnings'
        $ui.HeroSub.Text = 'Amber steps are worth a look. Send the report back to Claude.'
    } else {
        $ui.HeroTitle.Text = 'All checks passed'
        $ui.HeroSub.Text = 'Send the report back to Claude.'
    }
    $ui.OpenReport.IsEnabled = [bool]$script:ReportPath
    $ui.StartBtn.Content = 'RUN AGAIN'
}

# ---------------------------------------------------------------- background work

$sync = [hashtable]::Synchronized(@{
    Queue    = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    ChildPid = 0
})

$worker = {
    param($sync, $here, $mode, $ssid, $password, $lagSeconds, $answerDir)
    function Emit { $sync.Queue.Enqueue([object[]]$args) }
    try {
        $ErrorActionPreference = 'Stop'
        . (Join-Path $here 'm0-lib.ps1')

        if ($mode -eq 'PhoneHotspot') {
            Emit 'step' 'join' 'RUNNING' 'Connecting to the phone hotspot...'
            $current = if (Test-Connected) { Get-WlanField 'SSID' }
            if ((Test-Connected) -and -not $current) {
                Emit 'step' 'join' 'FAIL' 'Windows hides the Wi-Fi name. Settings > Privacy & security > Location > Let desktop apps access your location.'
                Emit 'done'
                return
            }
            if (-not $ssid) { $ssid = $current }
            if (-not $ssid) {
                Emit 'step' 'join' 'FAIL' 'Enter the phone hotspot name.'
                Emit 'done'
                return
            }
            $secure = if ($password) { ConvertTo-SecureString $password -AsPlainText -Force } else { $null }
            $null = Connect-PhoneHotspot $ssid $secure
            Emit 'step' 'join' 'PASS' "Connected to '$ssid'"
        } else {
            Emit 'step' 'join' 'SKIP' 'Laptop hotspot mode'
        }

        Emit 'step' 'firewall' 'RUNNING' 'Checking...'
        $needPin = $mode -eq 'PhoneHotspot' -and -not (Test-Pinned $ssid)
        if ((Test-FirewallReady) -and -not $needPin) {
            Emit 'step' 'firewall' 'PASS' 'Already set up, no admin needed'
        } else {
            Emit 'step' 'firewall' 'RUNNING' 'Approve the Windows admin prompt'
            $pin = if ($needPin) { $ssid } else { '' }
            if (Invoke-AdminSetup $here $pin) {
                Emit 'step' 'firewall' 'PASS' 'Firewall rules added, phone network pinned'
            } else {
                Emit 'step' 'firewall' 'WARN' 'Admin prompt declined: Moonlight may not connect'
            }
        }

        Emit 'phase' 'Running the hardware test...'
        $testArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$here\m0-hardware-proof.ps1`" -Mode $mode -LagSeconds $lagSeconds -GuiAnswerDir `"$answerDir`""
        if ($mode -eq 'PhoneHotspot') { $testArgs += ' -AssumeConnected' }
        $psi = New-Object Diagnostics.ProcessStartInfo 'powershell.exe', $testArgs
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.CreateNoWindow = $true
        $proc = [Diagnostics.Process]::Start($psi)
        $sync.ChildPid = $proc.Id
        while ($null -ne ($line = $proc.StandardOutput.ReadLine())) { Emit 'line' $line }
        $proc.WaitForExit()
        Emit 'done'
    } catch {
        Emit 'error' $_.Exception.Message
        Emit 'done'
    }
}

function Start-Run {
    $mode = if ($ui.ModeLaptop.IsChecked) { 'LaptopHotspot' } else { 'PhoneHotspot' }
    $ssid = $ui.SsidBox.Text.Trim()
    if ($mode -eq 'PhoneHotspot' -and -not $ssid -and -not (Test-Connected)) {
        $ui.HeroTitle.Text = 'Hotspot name needed'
        $ui.HeroSub.Text = 'Type the phone hotspot name, or connect the laptop to it first.'
        return
    }

    $script:Running = $true
    $script:ReportPath = $null
    $script:AnswerDir = Join-Path $env:TEMP "ophi-gui-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Force -Path $script:AnswerDir | Out-Null
    Set-Inputs $false
    $ui.OpenReport.IsEnabled = $false
    $ui.LogPanel.Children.Clear()
    $ui.HeroTitle.Text = 'Testing...'
    $ui.HeroSub.Text = 'Starting'
    $ui.Progress.IsIndeterminate = $true
    foreach ($id in $Steps.Keys) { Set-Step $id 'WAITING' $Steps[$id][1] }

    $lag = if ($ui.Dur180.IsChecked) { 180 } else { 90 }
    $ps = [powershell]::Create()
    $ps.Runspace = [runspacefactory]::CreateRunspace()
    $ps.Runspace.Open()
    [void]$ps.AddScript($worker).AddArgument($sync).AddArgument($here).AddArgument($mode).AddArgument($ssid).AddArgument($ui.PwBox.Password).AddArgument($lag).AddArgument($script:AnswerDir)
    [void]$ps.BeginInvoke()
}

function Send-Answer([string]$Answer) {
    $notes = ($ui.NotesBox.Text -replace '[\r\n|]+', ' ').Trim()
    Set-Content -Path (Join-Path $script:AnswerDir 'moonlight.txt') -Value "$Answer|$notes"
    $ui.AskPanel.Visibility = 'Collapsed'
    $ui.NotesBox.Text = ''
    $ui.HeroSub.Text = 'Finishing up...'
}

# ---------------------------------------------------------------- events

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(120)
$timer.Add_Tick({
    $item = $null
    while ($sync.Queue.TryDequeue([ref]$item)) {
        switch ($item[0]) {
            'step'  { Set-Step $item[1] $item[2] $item[3] }
            'phase' { $ui.HeroSub.Text = $item[1] }
            'line'  { Handle-Line $item[1] }
            'error' { Add-Log "Error: $($item[1])" $Colors.FAIL; $ui.HeroSub.Text = $item[1] }
            'done'  { Complete-Run }
        }
    }
})
$timer.Start()

$ui.TitleBar.Add_MouseLeftButtonDown({ $window.DragMove() })
$ui.MinBtn.Add_Click({ $window.WindowState = 'Minimized' })
$ui.CloseBtn.Add_Click({ $window.Close() })
$ui.StartBtn.Add_Click({ Start-Run })
$ui.AskYes.Add_Click({ Send-Answer 'y' })
$ui.AskNo.Add_Click({ Send-Answer 'n' })
$ui.AskSkip.Add_Click({ Send-Answer 's' })
$ui.OpenReport.Add_Click({ if ($script:ReportPath) { Start-Process notepad.exe $script:ReportPath } })
$ui.ModeLaptop.Add_Checked({ $ui.SsidRow.Visibility = 'Collapsed'; $ui.PwRow.Visibility = 'Collapsed' })
$ui.ModePhone.Add_Checked({ $ui.SsidRow.Visibility = 'Visible'; $ui.PwRow.Visibility = 'Visible' })

$window.Add_Closing({
    param($sender, $e)
    if (-not $script:Running) { return }
    $choice = [Windows.MessageBox]::Show('A test is running. Stop it and close?', 'OphiStreamer Test Kit', 'YesNo', 'Warning')
    if ($choice -ne 'Yes') { $e.Cancel = $true; return }
    # Windows undoes the lag fix when the test process dies; that's one of the things the test proves.
    if ($sync.ChildPid) { Stop-Process -Id $sync.ChildPid -Force -ErrorAction SilentlyContinue }
})

foreach ($id in $Steps.Keys) { $script:StepState[$id] = 'WAITING' }
if (Test-Connected) { $ui.SsidBox.Text = Get-WlanField 'SSID' }

if ($Screenshot) {
    $window.Add_ContentRendered({
        $root = $window.Content
        $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$root.ActualWidth), ([int]$root.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($root)
        $png = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $png.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
        $fs = [IO.File]::Create($Screenshot)
        try { $png.Save($fs) } finally { $fs.Close() }
        $window.Close()
    })
}

[void]$window.ShowDialog()

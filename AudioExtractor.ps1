<#
.SYNOPSIS
  Audio Extractor - a small personal app that saves the audio from YouTube videos.

.DESCRIPTION
  A friendly window around yt-dlp (downloading) and ffmpeg (converting).
  Paste one or more links, pick a format, press "Extract audio".

  Start it with "Audio Extractor.cmd", or:
    powershell -NoProfile -ExecutionPolicy Bypass -File AudioExtractor.ps1 [-Theme light|dark]
#>
[CmdletBinding()]
param(
    [ValidateSet('auto', 'light', 'dark')]
    [string]$Theme = 'auto'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$AppName = 'Audio Extractor'
$AppDir  = $PSScriptRoot

# ============================================================================ tools

function Find-Tool([string]$Name) {
    $cmd = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $link = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\$Name.exe"
    if (Test-Path -LiteralPath $link) { return $link }
    return $null
}

function Start-Console([string]$Command) {
    # Runs a command in a visible PowerShell window the user can watch.
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
    Start-Process powershell.exe -ArgumentList "-NoProfile -EncodedCommand $encoded"
}

$YtDlp  = Find-Tool 'yt-dlp'
$Ffmpeg = Find-Tool 'ffmpeg'
$JsRuntime = $null   # YouTube needs a JavaScript runtime for yt-dlp to work properly
foreach ($rt in 'deno', 'node', 'bun') { if (Find-Tool $rt) { $JsRuntime = $rt; break } }

if (-not $YtDlp) {
    $answer = [System.Windows.MessageBox]::Show(
        "yt-dlp is needed to download from YouTube, but it isn't installed.`n`nInstall it now with winget? A console window will open; start $AppName again once it finishes.",
        $AppName, [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
        Start-Console 'winget install --id yt-dlp.yt-dlp -e; Write-Host ""; Read-Host "Finished - press Enter to close"'
    }
    exit 1
}

# ============================================================================ settings

$SettingsPath = Join-Path $AppDir 'settings.json'
$DefaultOutDir = Join-Path ([Environment]::GetFolderPath('MyMusic')) 'YouTube Audio'
$Settings = @{
    Format  = 'mp3'
    Quality = '0'
    OutDir  = $DefaultOutDir
    Embed   = $true
}
if (Test-Path -LiteralPath $SettingsPath) {
    try {
        $saved = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($key in @($Settings.Keys)) {
            if ($null -ne $saved.$key -and "$($saved.$key)" -ne '') { $Settings[$key] = $saved.$key }
        }
    } catch { }
}

function Test-FolderUsable([string]$Path) {
    # Usable if the folder exists, or if its parent does (the app creates the last folder itself).
    try {
        $p = [Environment]::ExpandEnvironmentVariables("$Path".Trim())
        if (-not $p -or -not [IO.Path]::IsPathRooted($p)) { return $false }
        if (Test-Path -LiteralPath $p -PathType Container) { return $true }
        $parent = [IO.Path]::GetDirectoryName($p.TrimEnd('\'))
        return [bool]($parent -and (Test-Path -LiteralPath $parent -PathType Container))
    } catch { return $false }
}

# The saved folder may be on a drive this PC doesn't have (or one that isn't mounted yet,
# like a cloud drive right after login). Use the default for now, but remember the saved one.
$SavedOutDir = $null
if ([string]$Settings.OutDir -ne $DefaultOutDir -and -not (Test-FolderUsable $Settings.OutDir)) {
    $SavedOutDir = [string]$Settings.OutDir
    $Settings.OutDir = $DefaultOutDir
}

# ============================================================================ theme

if ($Theme -eq 'auto') {
    $Theme = 'light'
    try {
        $v = Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme
        if ($v -eq 0) { $Theme = 'dark' }
    } catch { }
}

$P = if ($Theme -eq 'dark') {
    @{
        Bg = '#16171A'; Surface = '#1F2125'; Hover = '#2A2D32'; Pressed = '#33363C'
        Border = '#2E3136'; BorderStrong = '#454951'; InputBg = '#18191C'; Track = '#2E3137'
        Text = '#ECEDEF'; Sub = '#9AA0A9'; Link = '#FF8287'
        Accent = '#D6383E'; AccentHover = '#E2484E'; AccentPressed = '#C42F35'; AccentText = '#FFFFFF'
    }
} else {
    @{
        Bg = '#F4F5F7'; Surface = '#FFFFFF'; Hover = '#F0F2F5'; Pressed = '#E6E9EE'
        Border = '#E1E4E9'; BorderStrong = '#C9CED6'; InputBg = '#FFFFFF'; Track = '#E6E8EC'
        Text = '#1A1C20'; Sub = '#5E6570'; Link = '#B8292F'
        Accent = '#D6383E'; AccentHover = '#C42F35'; AccentPressed = '#AE282E'; AccentText = '#FFFFFF'
    }
}

# ============================================================================ window layout

$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Audio Extractor" Width="620" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        Background="{{Bg}}" Foreground="{{Text}}"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
  <Window.Resources>
    <Style x:Key="Caption" TargetType="TextBlock">
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{{Sub}}"/>
      <Setter Property="Margin" Value="0,16,0,7"/>
    </Style>
    <Style x:Key="Hint" TargetType="TextBlock">
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Foreground" Value="{{Sub}}"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{{Surface}}"/>
      <Setter Property="BorderBrush" Value="{{Border}}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="10"/>
      <Setter Property="Padding" Value="18"/>
    </Style>

    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="{{Surface}}"/>
      <Setter Property="Foreground" Value="{{Text}}"/>
      <Setter Property="BorderBrush" Value="{{BorderStrong}}"/>
      <Setter Property="Padding" Value="8,5"/>
    </Style>

    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Background" Value="{{Surface}}"/>
      <Setter Property="Foreground" Value="{{Text}}"/>
      <Setter Property="BorderBrush" Value="{{BorderStrong}}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{{Hover}}"/></Trigger>
        <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="{{Pressed}}"/></Trigger>
      </Style.Triggers>
    </Style>

    <Style x:Key="PrimaryBtn" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="{{Accent}}"/>
      <Setter Property="BorderBrush" Value="{{Accent}}"/>
      <Setter Property="Foreground" Value="{{AccentText}}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="22,8"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="{{AccentHover}}"/>
          <Setter Property="BorderBrush" Value="{{AccentHover}}"/>
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
          <Setter Property="Background" Value="{{AccentPressed}}"/>
          <Setter Property="BorderBrush" Value="{{AccentPressed}}"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style x:Key="LinkBtn" TargetType="Button">
      <Setter Property="Foreground" Value="{{Link}}"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="Transparent" Padding="2,1">
              <TextBlock x:Name="Tx" Text="{Binding Content, RelativeSource={RelativeSource TemplatedParent}}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Tx" Property="TextDecorations" Value="Underline"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Tx" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Chip" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{{Text}}"/>
      <Setter Property="Background" Value="{{Surface}}"/>
      <Setter Property="BorderBrush" Value="{{BorderStrong}}"/>
      <Setter Property="Margin" Value="0,0,6,6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="6" Padding="13,6" MinWidth="58">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{{Hover}}"/></Trigger>
        <Trigger Property="IsChecked" Value="True">
          <Setter Property="Background" Value="{{Accent}}"/>
          <Setter Property="BorderBrush" Value="{{Accent}}"/>
          <Setter Property="Foreground" Value="{{AccentText}}"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
      </Style.Triggers>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{{Text}}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="Box" Width="17" Height="17" CornerRadius="4" BorderThickness="1"
                      BorderBrush="{{BorderStrong}}" Background="{{InputBg}}" VerticalAlignment="Center">
                <Path x:Name="Mark" Data="M3.5,8 L6.5,11 L11.5,4.5" Stroke="{{AccentText}}" StrokeThickness="2"
                      StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Box" Property="Background" Value="{{Accent}}"/>
                <Setter TargetName="Box" Property="BorderBrush" Value="{{Accent}}"/>
                <Setter TargetName="Mark" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{{InputBg}}"/>
      <Setter Property="Foreground" Value="{{Text}}"/>
      <Setter Property="BorderBrush" Value="{{BorderStrong}}"/>
      <Setter Property="CaretBrush" Value="{{Text}}"/>
      <Setter Property="SelectionBrush" Value="{{Accent}}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
              <ScrollViewer x:Name="PART_ContentHost" Focusable="False"
                            HorizontalScrollBarVisibility="{TemplateBinding ScrollViewer.HorizontalScrollBarVisibility}"
                            VerticalScrollBarVisibility="{TemplateBinding ScrollViewer.VerticalScrollBarVisibility}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="{{Accent}}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ProgressBar">
      <Setter Property="Height" Value="6"/>
      <Setter Property="Foreground" Value="{{Accent}}"/>
      <Setter Property="Background" Value="{{Track}}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ProgressBar">
            <Grid ClipToBounds="True">
              <Border x:Name="PART_Track" Background="{TemplateBinding Background}" CornerRadius="3"/>
              <Border x:Name="PART_Indicator" Background="{TemplateBinding Foreground}" CornerRadius="3" HorizontalAlignment="Left"/>
              <Border x:Name="Runner" Background="{TemplateBinding Foreground}" CornerRadius="3" Width="140"
                      HorizontalAlignment="Left" Visibility="Collapsed">
                <Border.RenderTransform><TranslateTransform x:Name="RunnerX" X="-140"/></Border.RenderTransform>
              </Border>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsIndeterminate" Value="True">
                <Setter TargetName="PART_Indicator" Property="Visibility" Value="Collapsed"/>
                <Setter TargetName="Runner" Property="Visibility" Value="Visible"/>
                <Trigger.EnterActions>
                  <BeginStoryboard x:Name="RunnerAnim">
                    <Storyboard RepeatBehavior="Forever">
                      <DoubleAnimation Storyboard.TargetName="RunnerX" Storyboard.TargetProperty="X"
                                       From="-140" To="620" Duration="0:0:1.5"/>
                    </Storyboard>
                  </BeginStoryboard>
                </Trigger.EnterActions>
                <Trigger.ExitActions><StopStoryboard BeginStoryboardName="RunnerAnim"/></Trigger.ExitActions>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border Padding="22,20,22,14">
    <StackPanel>

      <!-- Header -->
      <DockPanel Margin="0,0,0,18">
        <Border DockPanel.Dock="Left" Width="42" Height="42" CornerRadius="10" Background="{{Accent}}">
          <Path Data="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"
                Fill="White" Stretch="Uniform" Width="16" Height="22"/>
        </Border>
        <StackPanel Margin="13,0,0,0" VerticalAlignment="Center">
          <TextBlock Text="Audio Extractor" FontSize="19" FontWeight="SemiBold"/>
          <TextBlock Text="Paste YouTube links, get audio files." Style="{StaticResource Hint}" Margin="0,1,0,0"/>
        </StackPanel>
      </DockPanel>

      <!-- Settings -->
      <Border Style="{StaticResource Card}">
        <StackPanel>
          <DockPanel Margin="0,0,0,7">
            <Button x:Name="PasteBtn" DockPanel.Dock="Right" Content="Paste from clipboard" Style="{StaticResource LinkBtn}"/>
            <TextBlock Text="LINKS" Style="{StaticResource Caption}" Margin="0"/>
          </DockPanel>
          <Grid>
            <TextBox x:Name="Links" Height="80" AcceptsReturn="True" TextWrapping="NoWrap"
                     VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Hidden"/>
            <TextBlock x:Name="LinksHint" IsHitTestVisible="False" Margin="11,8,0,0" VerticalAlignment="Top"
                       Style="{StaticResource Hint}" FontSize="13"
                       Text="https://www.youtube.com/watch?v=...   (one link per line)"/>
          </Grid>

          <TextBlock Text="FORMAT" Style="{StaticResource Caption}"/>
          <WrapPanel x:Name="FormatPanel">
            <RadioButton GroupName="fmt" Tag="mp3"  Content="MP3"  Style="{StaticResource Chip}"
                         ToolTip="Plays everywhere. Converted from YouTube's audio stream."/>
            <RadioButton GroupName="fmt" Tag="m4a"  Content="M4A"  Style="{StaticResource Chip}"
                         ToolTip="AAC audio kept exactly as YouTube sends it (no re-encoding). Good for Apple devices."/>
            <RadioButton GroupName="fmt" Tag="opus" Content="Opus" Style="{StaticResource Chip}"
                         ToolTip="YouTube's highest-quality stream, kept as-is. Smallest files."/>
            <RadioButton GroupName="fmt" Tag="flac" Content="FLAC" Style="{StaticResource Chip}"
                         ToolTip="Lossless container, handy for editing. Bigger files; can't add quality beyond the source."/>
            <RadioButton GroupName="fmt" Tag="wav"  Content="WAV"  Style="{StaticResource Chip}"
                         ToolTip="Uncompressed audio for editors and DAWs. Very large files."/>
          </WrapPanel>

          <TextBlock x:Name="QualityLabel" Text="MP3 QUALITY" Style="{StaticResource Caption}" Margin="0,10,0,7"/>
          <WrapPanel x:Name="QualityPanel">
            <RadioButton GroupName="q" Tag="0"    Content="Best (VBR)" Style="{StaticResource Chip}"
                         ToolTip="Highest-quality variable bitrate (around 245 kbps). Recommended."/>
            <RadioButton GroupName="q" Tag="320K" Content="320 kbps" Style="{StaticResource Chip}"/>
            <RadioButton GroupName="q" Tag="192K" Content="192 kbps" Style="{StaticResource Chip}"/>
            <RadioButton GroupName="q" Tag="128K" Content="128 kbps" Style="{StaticResource Chip}"
                         ToolTip="Smallest files. Fine for speech and podcasts."/>
          </WrapPanel>

          <TextBlock Text="SAVE TO" Style="{StaticResource Caption}" Margin="0,10,0,7"/>
          <DockPanel>
            <Button x:Name="BrowseBtn" DockPanel.Dock="Right" Content="Browse..." Margin="8,0,0,0" Style="{StaticResource Btn}"/>
            <TextBox x:Name="OutDir" VerticalContentAlignment="Center"/>
          </DockPanel>

          <TextBlock Text="OPTIONS" Style="{StaticResource Caption}"/>
          <WrapPanel>
            <CheckBox x:Name="EmbedChk" Content="Add cover art &amp; tags" Margin="0,0,24,0"/>
            <CheckBox x:Name="PlaylistChk" Content="Whole playlist (when the link has one)"/>
          </WrapPanel>
          <StackPanel Orientation="Horizontal" Margin="0,12,0,0">
            <TextBlock Text="Only a clip:" VerticalAlignment="Center"/>
            <TextBox x:Name="ClipStart" Width="64" Margin="10,0,0,0" ToolTip="Start time, e.g. 1:30 (empty = from the beginning)"/>
            <TextBlock Text="to" Style="{StaticResource Hint}" Margin="8,0"/>
            <TextBox x:Name="ClipEnd" Width="64" ToolTip="End time, e.g. 2:45 (empty = to the end)"/>
            <TextBlock Text="e.g. 0:45 to 2:10  ·  blank = whole video" Style="{StaticResource Hint}" Margin="12,0,0,0"/>
          </StackPanel>
        </StackPanel>
      </Border>

      <!-- Actions -->
      <Grid Margin="0,16,0,0">
        <Button x:Name="OpenBtn" Content="Open folder" Style="{StaticResource Btn}" HorizontalAlignment="Left"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="CancelBtn" Content="Cancel" Style="{StaticResource Btn}" Margin="0,0,8,0" Visibility="Collapsed"/>
          <Button x:Name="GoBtn" Content="Extract audio" Style="{StaticResource PrimaryBtn}" ToolTip="Ctrl+Enter"/>
        </StackPanel>
      </Grid>

      <!-- Progress -->
      <Border Style="{StaticResource Card}" Margin="0,16,0,0" Padding="16,14">
        <StackPanel>
          <DockPanel>
            <TextBlock x:Name="Counter" DockPanel.Dock="Right" Style="{StaticResource Hint}" Margin="12,0,0,0"/>
            <TextBlock x:Name="NowTitle" Text="Ready" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
          </DockPanel>
          <ProgressBar x:Name="Bar" Margin="0,10,0,9" Minimum="0" Maximum="100" Value="0"/>
          <TextBlock x:Name="Status" Style="{StaticResource Hint}" TextTrimming="CharacterEllipsis"
                     Text="Tip: copy a YouTube link, then switch to this window - it gets pasted for you."/>
        </StackPanel>
      </Border>

      <TextBox x:Name="Log" Height="160" Margin="0,10,0,0" IsReadOnly="True" Visibility="Collapsed"
               FontFamily="Cascadia Mono, Consolas" FontSize="11.5" TextWrapping="Wrap"
               VerticalScrollBarVisibility="Auto"/>

      <!-- Footer -->
      <DockPanel Margin="0,12,0,0">
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <Button x:Name="LogBtn" Content="Show details" Style="{StaticResource LinkBtn}" Margin="0,0,14,0"/>
          <Button x:Name="ShortcutBtn" Content="Add to Start menu" Style="{StaticResource LinkBtn}" Margin="0,0,14,0"
                  ToolTip="Adds Audio Extractor to your Start menu and desktop"/>
          <Button x:Name="UpdateBtn" Content="Update yt-dlp" Style="{StaticResource LinkBtn}"
                  ToolTip="YouTube changes often - updating yt-dlp fixes most download errors"/>
        </StackPanel>
        <TextBlock x:Name="Footer" Style="{StaticResource Hint}" FontSize="11.5" TextTrimming="CharacterEllipsis" Text="Checking yt-dlp..."/>
      </DockPanel>
    </StackPanel>
  </Border>
</Window>
'@

foreach ($k in $P.Keys) { $Xaml = $Xaml.Replace("{{$k}}", $P[$k]) }
$window = [Windows.Markup.XamlReader]::Parse($Xaml)
$window.TaskbarItemInfo = New-Object System.Windows.Shell.TaskbarItemInfo

$ui = @{}
foreach ($name in 'PasteBtn', 'Links', 'LinksHint', 'FormatPanel', 'QualityLabel', 'QualityPanel', 'BrowseBtn', 'OutDir',
                  'EmbedChk', 'PlaylistChk', 'ClipStart', 'ClipEnd', 'OpenBtn', 'CancelBtn', 'GoBtn', 'Counter',
                  'NowTitle', 'Bar', 'Status', 'Log', 'LogBtn', 'ShortcutBtn', 'UpdateBtn', 'Footer') {
    $ui[$name] = $window.FindName($name)
}

# ============================================================================ state

$S = @{
    Running   = $false
    Cancelled = $false
    Proc      = $null
    OutTask   = $null
    ErrTask   = $null
    Urls      = @()
    Index     = 0
    Files     = New-Object System.Collections.Generic.List[string]
    Errors    = New-Object System.Collections.Generic.List[string]
    Failed    = New-Object System.Collections.Generic.List[string]
    Temp      = New-Object 'System.Collections.Generic.HashSet[string]'
    Seen      = New-Object 'System.Collections.Generic.HashSet[string]'
    ItemErrors = 0
    PlIndex   = ''
    PlCount   = ''
    LastFile  = $null
    LastAuto  = $null
    LogChars  = 0
    VerProc   = $null
    VerTask   = $null
    RecheckVersion = $false
    SavedOutDir = $SavedOutDir   # usual folder that was unavailable at startup
    LastFolderCheck = [DateTime]::MinValue
}

$FormatLabels = @{ mp3 = 'MP3'; m4a = 'M4A'; opus = 'Opus'; flac = 'FLAC'; wav = 'WAV' }
$TimeRx  = '^\d{1,3}(:\d{1,2}){0,2}(\.\d+)?$'
$YtUrlRx = '^(https?://)?(www\.|m\.|music\.)?(youtube\.com/(watch|shorts/|live/|playlist|embed/)|youtu\.be/)\S*$'
$Inv = [Globalization.CultureInfo]::InvariantCulture

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(80)

# ============================================================================ small UI helpers

function Show-Message([string]$Text, [string]$Kind = 'Information') {
    [void][System.Windows.MessageBox]::Show($window, $Text, $AppName,
        [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]$Kind)
}

function Write-Log([string]$Text) {
    $box = $ui.Log
    if ($S.LogChars -gt 300000) { $box.Text = $box.Text.Substring($box.Text.Length - 100000); $S.LogChars = 100000 }
    $box.AppendText($Text + "`r`n")
    $S.LogChars += $Text.Length + 2
    $box.ScrollToEnd()
}

function Set-Status([string]$Text) { $ui.Status.Text = $Text }

function Show-Log([bool]$Visible) {
    $ui.Log.Visibility = $(if ($Visible) { 'Visible' } else { 'Collapsed' })
    $ui.LogBtn.Content = $(if ($Visible) { 'Hide details' } else { 'Show details' })
    if ($Visible) { $ui.Log.ScrollToEnd() }
}

function Get-Checked($Panel) {
    foreach ($c in $Panel.Children) { if ($c.IsChecked) { return [string]$c.Tag } }
    return $null
}

function Set-Checked($Panel, [string]$Tag) {
    $hit = $false
    foreach ($c in $Panel.Children) { if ([string]$c.Tag -eq $Tag) { $c.IsChecked = $true; $hit = $true } }
    if (-not $hit) { $Panel.Children[0].IsChecked = $true }
}

function Update-FormatUi {
    $fmt = Get-Checked $ui.FormatPanel
    $ui.QualityPanel.IsEnabled = ($fmt -eq 'mp3') -and -not $S.Running
    $ui.QualityLabel.Opacity = $(if ($fmt -eq 'mp3') { 1 } else { 0.45 })
    $ui.EmbedChk.Content = $(if ($fmt -eq 'wav') { 'Add tags (WAV has no cover art)' } else { 'Add cover art & tags' })
}

function Update-Counter {
    $parts = @()
    if ($S.Urls.Count -gt 1) { $parts += "Link $($S.Index + 1) of $($S.Urls.Count)" }
    if ($S.PlIndex -match '^\d+$' -and $S.PlCount -match '^\d+$') { $parts += "Track $($S.PlIndex) of $($S.PlCount)" }
    $ui.Counter.Text = $parts -join '  ·  '
}

function Set-Progress([double]$Pct) {
    $ui.Bar.IsIndeterminate = $false
    $ui.Bar.Value = [Math]::Max(0, [Math]::Min(100, $Pct))
    # Overall progress on the taskbar button, across links and playlist tracks.
    $within = $Pct / 100
    if ($S.PlIndex -match '^\d+$' -and $S.PlCount -match '^\d+$' -and [int]$S.PlCount -gt 0) {
        $within = (([int]$S.PlIndex - 1) + $Pct / 100) / [int]$S.PlCount
    }
    $tb = $window.TaskbarItemInfo
    $tb.ProgressState = 'Normal'
    $tb.ProgressValue = [Math]::Min(1, ($S.Index + $within) / [Math]::Max(1, $S.Urls.Count))
}

function Set-Busy([bool]$Busy) {
    foreach ($n in 'Links', 'PasteBtn', 'FormatPanel', 'OutDir', 'BrowseBtn', 'EmbedChk', 'PlaylistChk',
                   'ClipStart', 'ClipEnd', 'UpdateBtn', 'ShortcutBtn') {
        $ui[$n].IsEnabled = -not $Busy
    }
    $ui.GoBtn.Visibility     = $(if ($Busy) { 'Collapsed' } else { 'Visible' })
    $ui.CancelBtn.Visibility = $(if ($Busy) { 'Visible' } else { 'Collapsed' })
    $ui.CancelBtn.IsEnabled  = $Busy
    Update-FormatUi
}

function Save-Settings {
    try {
        $o = [ordered]@{
            Format  = Get-Checked $ui.FormatPanel
            Quality = Get-Checked $ui.QualityPanel
            # Don't forget the usual folder just because it was unavailable this time.
            OutDir  = $(if ($S.SavedOutDir -and $ui.OutDir.Text.Trim() -eq $DefaultOutDir) { $S.SavedOutDir } else { $ui.OutDir.Text.Trim() })
            Embed   = [bool]$ui.EmbedChk.IsChecked
        }
        $o | ConvertTo-Json | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
    } catch { }
}

# ============================================================================ links & arguments

function Get-Links {
    $ok = New-Object System.Collections.Generic.List[string]
    $bad = New-Object System.Collections.Generic.List[string]
    foreach ($raw in ($ui.Links.Text -split '\s+')) {
        $l = $raw.Trim()
        if (-not $l) { continue }
        if ($l -match '^https?://\S+$') { $u = $l }
        elseif ($l -match '^(www\.|m\.|music\.)?(youtube\.com|youtu\.be)/') { $u = "https://$l" }
        elseif ($l -match '^[\w-]{11}$') { $u = "https://www.youtube.com/watch?v=$l" }   # bare video ID
        else { $bad.Add($l); continue }
        if (-not $ok.Contains($u)) { $ok.Add($u) }
    }
    return @{ Ok = $ok; Bad = $bad }
}

function ConvertTo-Seconds([string]$T) {
    $sec = 0.0
    foreach ($part in $T.Split(':')) { $sec = $sec * 60 + [double]::Parse($part, $Inv) }
    return $sec
}

function Join-Args($List) {
    # Quote each argument using the standard Windows command-line rules.
    $quoted = foreach ($item in $List) {
        $s = [string]$item
        if ($s -ne '' -and $s -notmatch '[\s"]') { $s; continue }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        $slashes = 0
        foreach ($ch in $s.ToCharArray()) {
            if ($ch -eq [char]'\') { $slashes++; continue }
            if ($ch -eq [char]'"') { [void]$sb.Append('\' * ($slashes * 2 + 1)).Append('"') }
            else { [void]$sb.Append('\' * $slashes).Append($ch) }
            $slashes = 0
        }
        [void]$sb.Append('\' * ($slashes * 2)).Append('"')
        $sb.ToString()
    }
    return ($quoted -join ' ')
}

function Get-YtArgs([string]$Url) {
    $a = New-Object System.Collections.Generic.List[string]
    $a.AddRange([string[]]@('--ignore-config', '--encoding', 'utf-8', '--color', 'never', '--newline',
                            '--no-quiet', '--no-mtime', '-x'))
    $a.Add($(if ($S.Playlist) { '--yes-playlist' } else { '--no-playlist' }))
    if ($JsRuntime -and $JsRuntime -ne 'deno') { $a.AddRange([string[]]@('--js-runtimes', $JsRuntime)) }

    switch ($S.Format) {
        'mp3'  { $a.AddRange([string[]]@('--audio-format', 'mp3', '--audio-quality', $S.Quality)) }
        'm4a'  { $a.AddRange([string[]]@('-f', 'ba[ext=m4a]/ba/b', '--audio-format', 'm4a')) }
        'opus' { $a.AddRange([string[]]@('--audio-format', 'opus')) }
        'flac' { $a.AddRange([string[]]@('--audio-format', 'flac')) }
        'wav'  { $a.AddRange([string[]]@('--audio-format', 'wav')) }
    }
    if ($S.Embed) {
        $a.Add('--embed-metadata')
        if ($S.Format -ne 'wav') { $a.Add('--embed-thumbnail') }
    }

    $suffix = ''
    if ($S.ClipStart -or $S.ClipEnd) {
        $from = $(if ($S.ClipStart) { $S.ClipStart } else { '0' })
        $to   = $(if ($S.ClipEnd) { $S.ClipEnd } else { 'inf' })
        # --force-keyframes-at-cuts makes the cut exact; without it WebM/Opus sources ignore the start time.
        $a.AddRange([string[]]@('--download-sections', "*$from-$to", '--force-keyframes-at-cuts'))
        $suffix = ' (clip {0}-{1})' -f $from.Replace(':', '.'), $(if ($S.ClipEnd) { $S.ClipEnd.Replace(':', '.') } else { 'end' })
    }

    $a.AddRange([string[]]@(
        '-P', $S.OutDir,
        '-o', "%(playlist_index&{} - |)s%(title)s$suffix.%(ext)s",
        '--print', 'before_dl:ITEM|%(playlist_index|)s|%(n_entries|)s|%(title)s',
        '--print', 'after_move:FILE|%(filepath)s',
        '--progress-template', 'download:PROG|%(progress._percent)s|%(progress._speed_str)s|%(progress._eta_str)s',
        '--progress-template', 'postprocess:PP|%(progress.status)s|%(progress.postprocessor)s',
        '--', $Url))
    return , $a
}

# ============================================================================ running yt-dlp

function Start-Run {
    if ($S.Running) { return }

    $links = Get-Links
    if ($links.Bad.Count) {
        Show-Message ("These don't look like links:`n`n" + ($links.Bad -join "`n")) 'Warning'
        return
    }
    if (-not $links.Ok.Count) {
        Set-Status 'Paste at least one YouTube link first.'
        [void]$ui.Links.Focus()
        return
    }
    if (-not $Ffmpeg) {
        Show-Message "ffmpeg isn't installed, so the audio can't be converted.`n`nInstall it from a terminal with:`nwinget install yt-dlp.FFmpeg" 'Warning'
        return
    }

    $start = $ui.ClipStart.Text.Trim()
    $end   = $ui.ClipEnd.Text.Trim()
    foreach ($t in @($start, $end)) {
        if ($t -and $t -notmatch $TimeRx) {
            Show-Message "Clip times look like 1:30, 0:45 or 1:02:03 (got `"$t`")." 'Warning'
            return
        }
    }
    if ($start -and $end -and (ConvertTo-Seconds $end) -le (ConvertTo-Seconds $start)) {
        Show-Message 'The clip has to end after it starts.' 'Warning'
        return
    }

    $dir = [Environment]::ExpandEnvironmentVariables($ui.OutDir.Text.Trim())
    if (-not $dir) { Show-Message 'Choose a folder to save into.' 'Warning'; return }
    try {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $dir = (Resolve-Path -LiteralPath $dir).ProviderPath
    } catch {
        Show-Message "Can't use that folder:`n$($_.Exception.Message)" 'Warning'
        return
    }

    $S.Urls = @($links.Ok)
    $S.Index = 0
    $S.Files.Clear(); $S.Errors.Clear(); $S.Failed.Clear()
    $S.Cancelled = $false
    $S.LastFile = $null
    $S.Format = Get-Checked $ui.FormatPanel
    $S.Quality = Get-Checked $ui.QualityPanel
    $S.Embed = [bool]$ui.EmbedChk.IsChecked
    $S.Playlist = [bool]$ui.PlaylistChk.IsChecked
    $S.ClipStart = $start
    $S.ClipEnd = $end
    $S.OutDir = $dir
    foreach ($u in $S.Urls) { [void]$S.Seen.Add($u) }
    Save-Settings

    $S.Running = $true
    Set-Busy $true
    $ui.Status.ToolTip = $null
    $ui.Log.Clear(); $S.LogChars = 0
    Write-Log "Saving $($FormatLabels[$S.Format]) files to $dir"
    Start-Item
    $timer.Start()
}

function Start-Item {
    $url = $S.Urls[$S.Index]
    $S.ItemErrors = 0
    $S.PlIndex = ''; $S.PlCount = ''
    $S.Temp.Clear()
    $ui.NowTitle.Text = 'Fetching video info...'
    $ui.Bar.IsIndeterminate = $true
    Set-Status $url
    Update-Counter
    Write-Log ''
    Write-Log "-> $url"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $YtDlp
    $psi.Arguments = Join-Args (Get-YtArgs $url)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding $false
    $psi.StandardErrorEncoding = New-Object System.Text.UTF8Encoding $false
    $psi.WorkingDirectory = $S.OutDir
    $psi.EnvironmentVariables['PYTHONUTF8'] = '1'

    try {
        $S.Proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        $S.Proc = $null
        $S.Errors.Add("Couldn't start yt-dlp: $($_.Exception.Message)")
        $S.Failed.Add($url)
        Write-Log "x Couldn't start yt-dlp: $($_.Exception.Message)"
        Move-Next
        return
    }
    $S.OutTask = $S.Proc.StandardOutput.ReadLineAsync()
    $S.ErrTask = $S.Proc.StandardError.ReadLineAsync()
}

function Read-Stream([string]$Which) {
    # Drains whatever lines are ready without ever blocking the window.
    $key = "${Which}Task"
    for ($i = 0; $i -lt 400; $i++) {
        $task = $S[$key]
        if (-not $task -or -not $task.IsCompleted) { return }
        $line = $null
        if (-not $task.IsFaulted -and -not $task.IsCanceled) { $line = $task.Result }
        if ($null -eq $line) { $S[$key] = $null; return }
        Receive-Line $line
        if (-not $S.Proc) { return }
        $reader = $(if ($Which -eq 'Out') { $S.Proc.StandardOutput } else { $S.Proc.StandardError })
        $S[$key] = $reader.ReadLineAsync()
    }
}

function Receive-Line([string]$Line) {
    if ($Line.StartsWith('PROG|')) {
        $f = $Line.Split('|')
        $pct = 0.0
        $known = [double]::TryParse($f[1], [Globalization.NumberStyles]::Float, $Inv, [ref]$pct)
        if ($known) { Set-Progress $pct } else { $ui.Bar.IsIndeterminate = $true }
        $txt = $(if ($known) { 'Downloading...  {0:0}%' -f $pct } else { 'Downloading...' })
        $speed = $f[2].Trim()
        $eta = $f[3].Trim()
        if ($speed -and $speed -notmatch 'NA|Unknown') { $txt += "  ·  $speed" }
        if ($eta -and $eta -notmatch 'NA|Unknown' -and $eta -ne '00:00') { $txt += "  ·  $eta left" }
        Set-Status $txt
        return
    }
    if ($Line.StartsWith('ITEM|')) {
        $f = $Line.Split([char[]]@('|'), 4)
        $S.PlIndex = $f[1]; $S.PlCount = $f[2]
        $S.Temp.Clear()
        $ui.NowTitle.Text = $f[3]
        Update-Counter
        Set-Progress 0
        Set-Status 'Starting download...'
        Write-Log "   $($f[3])"
        return
    }
    if ($Line.StartsWith('PP|')) {
        $f = $Line.Split('|')
        if ($f[1] -eq 'started') {
            $msg = switch ($f[2]) {
                'ExtractAudio'   { "Converting to $($FormatLabels[$S.Format])..." }
                'Metadata'       { 'Writing tags...' }
                'EmbedThumbnail' { 'Adding cover art...' }
                'MoveFiles'      { 'Finishing up...' }
                default          { "Processing ($($f[2]))..." }
            }
            Set-Status $msg
            $ui.Bar.IsIndeterminate = $true
        }
        return
    }
    if ($Line.StartsWith('FILE|')) {
        $path = $Line.Substring(5)
        if (-not $S.Files.Contains($path)) { $S.Files.Add($path) }
        $S.LastFile = $path
        $S.Temp.Clear()
        Set-Progress 100
        Set-Status "Saved $([IO.Path]::GetFileName($path))"
        Write-Log "   saved: $path"
        return
    }

    # Remember intermediate files so a cancelled item doesn't leave junk behind.
    if ($Line -match '^\[download\] Destination: (.+)$') {
        $f = $Matches[1]
        foreach ($x in $f, "$f.part", "$f.ytdl") { [void]$S.Temp.Add($x) }
    } elseif ($Line -match '^\[info\] Writing video thumbnail \S+ to: (.+)$') {
        [void]$S.Temp.Add($Matches[1])
    } elseif ($Line -match '^\[ThumbnailsConvertor\] Converting thumbnail "(.+)" to (\w+)') {
        [void]$S.Temp.Add([IO.Path]::ChangeExtension($Matches[1], $Matches[2]))
    } elseif ($Line -match '^\[ExtractAudio\] Destination: (.+)$') {
        [void]$S.Temp.Add($Matches[1])
    }

    # Skip noise: yt-dlp probing thumbnail sizes, and ffmpeg's chatter when cutting clips.
    if ($Line -match '^\[info\] (Downloading video thumbnail|Video Thumbnail) ') { return }
    if ($Line -match '^(\s|Input #|Output #|Stream mapping|Press \[q\]|size=|\[\w+ @ |\[out#)') { return }

    if ($Line -match '^ERROR:\s*(.*)$') {
        $S.ItemErrors++
        $S.Errors.Add($Matches[1])
        Write-Log "x $Line"
        return
    }
    Write-Log $Line
}

function Remove-TempFiles {
    foreach ($f in @($S.Temp)) {
        try { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } } catch { }
    }
    $S.Temp.Clear()
}

function Complete-Item {
    $p = $S.Proc
    $S.Proc = $null
    $S.OutTask = $null; $S.ErrTask = $null
    $code = -1
    try { $code = $p.ExitCode } catch { }
    try { $p.Dispose() } catch { }

    if ($S.Cancelled) {
        Remove-TempFiles
        Finish-Run
        return
    }
    if ($code -ne 0 -or $S.ItemErrors -gt 0) {
        $S.Failed.Add($S.Urls[$S.Index])
        if ($S.ItemErrors -eq 0) {
            $S.Errors.Add("yt-dlp stopped with exit code $code")
            Write-Log "x yt-dlp stopped with exit code $code"
        }
    }
    Move-Next
}

function Move-Next {
    $S.Index++
    if ($S.Index -lt $S.Urls.Count) { Start-Item } else { Finish-Run }
}

function Finish-Run {
    $S.Running = $false
    Set-Busy $false
    $ui.Counter.Text = ''
    $ui.Bar.IsIndeterminate = $false
    $tb = $window.TaskbarItemInfo
    $n = $S.Files.Count
    $files = $(if ($n -eq 1) { '1 file' } else { "$n files" })

    if ($S.Cancelled) {
        $ui.NowTitle.Text = 'Cancelled'
        Set-Status "Stopped. $files saved before cancelling."
        $ui.Bar.Value = 0
        $tb.ProgressState = 'None'
        Write-Log 'Cancelled.'
        return
    }

    # Keep only the links that failed in the box, so they're easy to retry.
    $ui.Links.Text = (@($S.Failed) | Select-Object -Unique) -join "`r`n"

    if ($S.Errors.Count -eq 0) {
        $ui.NowTitle.Text = "Done - $files saved"
        Set-Status "Saved to $($S.OutDir)"
        $ui.Bar.Value = 100
        $tb.ProgressState = 'None'
        [System.Media.SystemSounds]::Asterisk.Play()
    } else {
        $e = $S.Errors.Count
        $ui.NowTitle.Text = $(if ($n) { "Finished: $files saved, $e problem$(if ($e -gt 1) {'s'})" } else { "Couldn't extract audio" })
        Set-Status $S.Errors[0]
        $ui.Status.ToolTip = ($S.Errors -join "`n")
        $tb.ProgressState = 'Error'
        $tb.ProgressValue = 1
        Show-Log $true
        [System.Media.SystemSounds]::Exclamation.Play()
    }
    Write-Log ''
    Write-Log "Finished: $files saved, $($S.Errors.Count) error(s)."
}

function Stop-Run([switch]$Wait) {
    if (-not $S.Running) { return }
    $S.Cancelled = $true
    $ui.CancelBtn.IsEnabled = $false
    Set-Status 'Stopping...'
    $p = $S.Proc
    if ($p -and -not $p.HasExited) {
        # Kill yt-dlp together with the ffmpeg/deno processes it started.
        $k = New-Object System.Diagnostics.ProcessStartInfo 'taskkill.exe', "/PID $($p.Id) /T /F"
        $k.CreateNoWindow = $true
        $k.UseShellExecute = $false
        try { [void][System.Diagnostics.Process]::Start($k).WaitForExit(5000) } catch { }
        if ($Wait) { try { [void]$p.WaitForExit(3000) } catch { } }
    }
    if ($Wait) { Remove-TempFiles }
}

# ============================================================================ version check

function Start-VersionCheck {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo $YtDlp, '--version'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $S.VerProc = [System.Diagnostics.Process]::Start($psi)
        $S.VerTask = $S.VerProc.StandardOutput.ReadToEndAsync()
        $timer.Start()
    } catch {
        $ui.Footer.Text = 'yt-dlp version unknown'
    }
}

function Complete-VersionCheck {
    $v = ''
    try { $v = "$($S.VerTask.Result)".Trim() } catch { }
    $S.VerTask = $null
    try { $S.VerProc.Dispose() } catch { }
    $S.VerProc = $null

    $parts = @(
        $(if ($v) { "yt-dlp $v" } else { 'yt-dlp' }),
        $(if ($Ffmpeg) { 'ffmpeg ✓' } else { 'ffmpeg missing' }),
        $(if ($JsRuntime) { "$JsRuntime ✓" } else { 'no JS runtime' })
    )
    $ui.Footer.Text = $parts -join '  ·  '
    $ui.Footer.ToolTip = "yt-dlp: $YtDlp`nffmpeg: $(if ($Ffmpeg) { $Ffmpeg } else { 'not found' })"

    if ($v -match '^(\d{4})\.(\d{1,2})\.(\d{1,2})') {
        try {
            $age = ((Get-Date) - (Get-Date -Year $Matches[1] -Month $Matches[2] -Day $Matches[3])).TotalDays
            if ($age -gt 60) {
                $ui.UpdateBtn.Content = 'Update yt-dlp (recommended)'
                $ui.UpdateBtn.ToolTip = "Your yt-dlp is $([int]$age) days old. YouTube changes often, and updating fixes most download errors."
            } else {
                $ui.UpdateBtn.Content = 'Update yt-dlp'
            }
        } catch { }
    }
}

# ============================================================================ icon & shortcut

function New-AppIcon([int]$Size) {
    $dv = New-Object System.Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $bg = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($P.Accent))
    $r = $Size * 0.22
    $dc.DrawRoundedRectangle($bg, $null, (New-Object System.Windows.Rect 0, 0, $Size, $Size), $r, $r)
    $note = [System.Windows.Media.Geometry]::Parse('M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z')
    $k = $Size / 32.0
    $dc.PushTransform((New-Object System.Windows.Media.MatrixTransform $k, 0, 0, $k, ($Size / 8.0), ($Size / 8.0)))
    $dc.DrawGeometry([System.Windows.Media.Brushes]::White, $null, $note)
    $dc.Pop()
    $dc.Close()
    $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap $Size, $Size, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dv)
    $bmp.Freeze()
    return $bmp
}

function Save-AppIcon([string]$Path) {
    # A .ico file holding PNG images at a few sizes.
    $sizes = 16, 24, 32, 48, 64, 256
    $pngs = foreach ($sz in $sizes) {
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create((New-AppIcon $sz)))
        $ms = New-Object System.IO.MemoryStream
        $enc.Save($ms)
        , $ms.ToArray()
    }
    $fs = [System.IO.File]::Create($Path)
    $w = New-Object System.IO.BinaryWriter $fs
    try {
        $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $dim = $(if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] })
            $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
            $w.Write([uint16]1); $w.Write([uint16]32)
            $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
            $offset += $pngs[$i].Length
        }
        foreach ($png in $pngs) { $w.Write([byte[]]$png) }
    } finally { $w.Close() }
}

function Install-Shortcuts {
    $icon = Join-Path $AppDir 'AudioExtractor.ico'
    Save-AppIcon $icon
    $shell = New-Object -ComObject WScript.Shell
    $places = @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))
    foreach ($place in $places) {
        $lnk = $shell.CreateShortcut((Join-Path $place "$AppName.lnk"))
        $lnk.TargetPath = Join-Path $PSHOME 'powershell.exe'
        $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
        $lnk.WorkingDirectory = $AppDir
        $lnk.IconLocation = "$icon,0"
        $lnk.WindowStyle = 7
        $lnk.Description = 'Save the audio from YouTube videos'
        $lnk.Save()
    }
}

function Set-TitleBarColors {
    # Matches the Windows title bar to the app's theme (Windows 11; ignored elsewhere).
    try {
        if (-not ('AudioExtractorNative.Dwm' -as [type])) {
            Add-Type -Namespace AudioExtractorNative -Name Dwm -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int value, int size);
'@
        }
        $h = (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle
        $toRef = { param($hex) $c = [Convert]::ToInt32($hex.Substring(1), 16); (($c -shr 16) -band 0xFF) -bor ($c -band 0xFF00) -bor (($c -band 0xFF) -shl 16) }
        $dark = [int]($Theme -eq 'dark')
        $caption = & $toRef $P.Bg
        $text = & $toRef $P.Text
        [void][AudioExtractorNative.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$dark, 4)
        [void][AudioExtractorNative.Dwm]::DwmSetWindowAttribute($h, 35, [ref]$caption, 4)
        [void][AudioExtractorNative.Dwm]::DwmSetWindowAttribute($h, 36, [ref]$text, 4)
    } catch { }
}

# ============================================================================ events

$timer.Add_Tick({
    try {
        if ($S.VerTask -and $S.VerTask.IsCompleted) { Complete-VersionCheck }
        if ($S.Proc) {
            Read-Stream 'Out'
            Read-Stream 'Err'
            if ($S.Proc -and -not $S.OutTask -and -not $S.ErrTask -and $S.Proc.WaitForExit(50)) { Complete-Item }
        }
        if (-not $S.Running -and -not $S.VerTask) { $timer.Stop() }
    } catch {
        Write-Log "Internal error: $($_.Exception.Message)"
        if ($S.Running) {
            $S.Errors.Add("Internal error: $($_.Exception.Message)")
            if ($S.Proc) { Stop-Run } else { Finish-Run }
        }
    }
})

foreach ($chip in $ui.FormatPanel.Children) { $chip.Add_Checked({ Update-FormatUi }) }

$ui.Links.Add_TextChanged({
    $ui.LinksHint.Visibility = $(if ($ui.Links.Text.Length) { 'Collapsed' } else { 'Visible' })
})

$ui.PasteBtn.Add_Click({
    $t = ''
    try { $t = [System.Windows.Clipboard]::GetText().Trim() } catch { }
    if (-not $t) { Set-Status 'The clipboard has no text in it.'; return }
    $cur = $ui.Links.Text.TrimEnd()
    $ui.Links.Text = $(if ($cur) { "$cur`r`n$t" } else { $t })
    $ui.Links.CaretIndex = $ui.Links.Text.Length
    [void]$ui.Links.Focus()
})

$ui.BrowseBtn.Add_Click({
    try {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Choose where to save the audio files'
        $dlg.ShowNewFolderButton = $true
        $cur = [Environment]::ExpandEnvironmentVariables($ui.OutDir.Text.Trim())
        if ($cur -and (Test-Path -LiteralPath $cur)) { $dlg.SelectedPath = $cur }
        $owner = New-Object System.Windows.Forms.NativeWindow
        $owner.AssignHandle((New-Object System.Windows.Interop.WindowInteropHelper $window).Handle)
        try {
            if ($dlg.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
                $ui.OutDir.Text = $dlg.SelectedPath
                $S.SavedOutDir = $null   # a folder picked on purpose replaces the old one
                Save-Settings
            }
        } finally { $owner.ReleaseHandle(); $dlg.Dispose() }
    } catch { Show-Message $_.Exception.Message 'Error' }
})

$ui.OpenBtn.Add_Click({
    try {
        if ($S.LastFile -and (Test-Path -LiteralPath $S.LastFile)) {
            Start-Process explorer.exe -ArgumentList "/select,`"$($S.LastFile)`""
        } else {
            $d = [Environment]::ExpandEnvironmentVariables($ui.OutDir.Text.Trim())
            if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
            Start-Process explorer.exe -ArgumentList "`"$d`""
        }
    } catch { Show-Message $_.Exception.Message 'Error' }
})

$ui.GoBtn.Add_Click({
    try { Start-Run } catch { Show-Message "Something went wrong: $($_.Exception.Message)" 'Error'; if ($S.Running) { Finish-Run } }
})

$ui.CancelBtn.Add_Click({ Stop-Run })

$ui.LogBtn.Add_Click({ Show-Log ($ui.Log.Visibility -ne 'Visible') })

$ui.ShortcutBtn.Add_Click({
    try {
        Install-Shortcuts
        Set-Status "Added `"$AppName`" to your Start menu and desktop."
    } catch { Show-Message "Couldn't create the shortcuts: $($_.Exception.Message)" 'Error' }
})

$ui.UpdateBtn.Add_Click({
    try {
        $cmd = $(if ($YtDlp -match '\\WinGet\\') { 'winget upgrade --id yt-dlp.yt-dlp -e' }
                 else { "& '$($YtDlp.Replace("'", "''"))' -U" })
        Start-Console ($cmd + '; Write-Host ""; Read-Host "Done - press Enter to close"')
        $S.RecheckVersion = $true
    } catch { Show-Message $_.Exception.Message 'Error' }
})

$window.Add_PreviewKeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return -and
        ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        $e.Handled = $true
        try { Start-Run } catch { Show-Message "Something went wrong: $($_.Exception.Message)" 'Error' }
    }
})

$window.Add_Activated({
    try {
        if ($S.RecheckVersion -and -not $S.VerTask) { $S.RecheckVersion = $false; Start-VersionCheck }
        # Switch back to the usual folder once it's available again (e.g. a cloud drive finished mounting).
        if ($S.SavedOutDir -and -not $S.Running -and $ui.OutDir.Text.Trim() -eq $DefaultOutDir -and
            ((Get-Date) - $S.LastFolderCheck).TotalSeconds -ge 10) {
            $S.LastFolderCheck = Get-Date
            if (Test-FolderUsable $S.SavedOutDir) {
                $ui.OutDir.Text = $S.SavedOutDir
                $S.SavedOutDir = $null
                Set-Status "Your usual folder is available again: $($ui.OutDir.Text)"
            }
        }
        # Copied a YouTube link? Fill it in when the window comes back into focus.
        if ($S.Running -or $ui.Links.Text.Trim()) { return }
        $t = [System.Windows.Clipboard]::GetText().Trim()
        if ($t -and $t -match $YtUrlRx -and $t -ne $S.LastAuto -and -not $S.Seen.Contains($t)) {
            $ui.Links.Text = $t
            $S.LastAuto = $t
            Set-Status 'Pasted the link from your clipboard. Press Extract audio when ready.'
        }
    } catch { }
})

$window.Add_SourceInitialized({ Set-TitleBarColors })

$window.Add_Loaded({
    Start-VersionCheck
    if ($S.SavedOutDir) {
        $S.LastFolderCheck = Get-Date
        Set-Status "Your usual folder ($($S.SavedOutDir)) isn't available, so files will go to Music\YouTube Audio for now."
    }
    if (-not $JsRuntime) {
        Set-Status 'YouTube needs Deno for reliable downloads. Install it with: winget install DenoLand.Deno'
    }
    [void]$window.Activate()
})

$window.Add_Closing({
    param($sender, $e)
    if ($S.Running) {
        $r = [System.Windows.MessageBox]::Show($window, 'Audio is still being extracted. Stop and quit?', $AppName,
            [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($r -ne [System.Windows.MessageBoxResult]::Yes) { $e.Cancel = $true; return }
        Stop-Run -Wait
    }
    $timer.Stop()
    Save-Settings
})

# ============================================================================ start

[System.Windows.Forms.Application]::EnableVisualStyles()
Set-Checked $ui.FormatPanel $Settings.Format
Set-Checked $ui.QualityPanel ([string]$Settings.Quality)
$ui.OutDir.Text = $Settings.OutDir
$ui.EmbedChk.IsChecked = [bool]$Settings.Embed
Update-FormatUi
try { $window.Icon = New-AppIcon 64 } catch { }

[void]$window.ShowDialog()

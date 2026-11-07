#requires -Version 5.1
<#
  Bluetooth Battery Widget
  A small desktop widget that shows battery levels of Bluetooth devices
  connected to this PC (whatever Windows itself reports in Settings > Bluetooth).

  Run:   double-click launch.vbs   (or: powershell -STA -ExecutionPolicy Bypass -File BluetoothBatteryWidget.ps1)
  Use:   drag to move, right-click for options.
#>

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$AppName      = 'BTBatteryWidget'
$DataDir      = Join-Path $env:LOCALAPPDATA $AppName
$SettingsPath = Join-Path $DataDir 'settings.json'
$LogPath      = Join-Path $DataDir 'error.log'
$StartupLnk   = Join-Path ([Environment]::GetFolderPath('Startup')) 'Bluetooth Battery Widget.lnk'
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

function Write-Log($msg) {
    try { Add-Content -Path $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format s), $msg) } catch {}
}

# ---------- single instance ----------
$createdNew = $false
$script:Mutex = New-Object System.Threading.Mutex($true, "Local\$AppName", [ref]$createdNew)
if (-not $createdNew) { exit }

# ---------- settings ----------
$script:Settings = [pscustomobject]@{
    Left = $null; Top = $null
    Topmost = $false
    ShowDisconnected = $false
    RefreshSeconds = 60
    Aliases = @{}          # MAC -> custom display name
}
if (Test-Path $SettingsPath) {
    try {
        $saved = Get-Content $SettingsPath -Raw | ConvertFrom-Json
        foreach ($p in $saved.PSObject.Properties) {
            if ($p.Name -eq 'Aliases') {
                if ($p.Value) { foreach ($a in $p.Value.PSObject.Properties) { $script:Settings.Aliases[$a.Name] = [string]$a.Value } }
            }
            elseif ($script:Settings.PSObject.Properties[$p.Name]) { $script:Settings.($p.Name) = $p.Value }
        }
    } catch { Write-Log "settings: $_" }
}
function Save-Settings {
    try { $script:Settings | ConvertTo-Json | Set-Content -Path $SettingsPath -Encoding UTF8 } catch { Write-Log "save: $_" }
}

# ---------- data collection (runs in a background runspace) ----------
$Collector = {
    $ErrorActionPreference = 'SilentlyContinue'
    $KeyBattery = '{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2'   # DEVPKEY_Bluetooth_Battery
    $KeyConnected = '{83DA6326-97A6-4088-9453-A1923F573B29} 15'  # DEVPKEY_Device_IsConnected

    function Get-Mac([string]$id) {
        # The device MAC is the last 12-hex-digit run in the final path segment
        $seg = ($id -split '\\')[-1]
        $m = [regex]::Matches($seg, '[0-9A-Fa-f]{12}')
        if ($m.Count) { $m[$m.Count - 1].Value.ToUpper() }
    }

    $all = @(Get-PnpDevice -PresentOnly)

    # Parent device nodes: friendly name + connected state
    $dev = @{}
    foreach ($d in $all) {
        if ($d.InstanceId -notmatch '^(BTHENUM|BTHLE)\\DEV_') { continue }
        $mac = Get-Mac $d.InstanceId
        if (-not $mac) { continue }
        $c = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName $KeyConnected -ErrorAction SilentlyContinue).Data
        $dev[$mac] = @{ Name = $d.FriendlyName; Connected = [bool]$c }
    }

    # Nodes carrying a battery level (LE device node, or classic hands-free service node)
    $batt = @{}
    foreach ($d in $all) {
        if ($d.InstanceId -notmatch '^(BTHLE\\DEV_|BTHENUM\\\{0000(111E|111F|1108|1112|1124)-|BTHHFENUM\\)') { continue }
        $v = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName $KeyBattery -ErrorAction SilentlyContinue).Data
        if ($null -eq $v) { continue }
        $mac = Get-Mac $d.InstanceId
        if (-not $mac) { continue }
        $isAudio = $d.InstanceId -match '\{0000(111E|111F|110B|110A|1108|1112)-'
        if (-not $batt.ContainsKey($mac) -or [int]$v -gt $batt[$mac].Level) {
            $batt[$mac] = @{ Level = [int]$v; Name = $d.FriendlyName; Audio = $isAudio }
        }
    }

    # HID class (keyboard / mouse) for LE HID devices, matched by MAC in the instance id
    $hid = @{}
    foreach ($d in $all) {
        if ($d.Class -ne 'Keyboard' -and $d.Class -ne 'Mouse') { continue }
        $m = [regex]::Match($d.InstanceId, '_([0-9A-Fa-f]{12})(&|\\)')
        if ($m.Success) { $hid[$m.Groups[1].Value.ToUpper()] = $d.Class }
    }

    foreach ($mac in $batt.Keys) {
        $b = $batt[$mac]
        $name = if ($dev.ContainsKey($mac) -and $dev[$mac].Name) { $dev[$mac].Name }
                else { $b.Name -replace '\s+(Hands-Free( AG)?( Audio)?|Avrcp Transport|Stereo)$', '' }
        $connected = if ($dev.ContainsKey($mac)) { $dev[$mac].Connected } else { $true }

        $kind = 'generic'
        if     ($hid[$mac] -eq 'Keyboard') { $kind = 'keyboard' }
        elseif ($hid[$mac] -eq 'Mouse')    { $kind = 'mouse' }
        elseif ($name -match '(?i)controller|gamepad|xbox|dualsense|dualshock|joy-?con|8bitdo') { $kind = 'controller' }
        elseif ($name -match '(?i)keys|keyboard|\bkb\b|craft') { $kind = 'keyboard' }
        elseif ($name -match '(?i)mouse|\blift\b|mx master|mx anywhere|mx ergo|mx vertical|trackball|pebble|\bm\d{3}\b') { $kind = 'mouse' }
        elseif ($name -match '(?i)speaker|srs-|soundlink|soundcore|boom|\bflip\b|\bcharge\b|\bpulse\b') { $kind = 'speaker' }
        elseif ($name -match '(?i)pen\b|stylus') { $kind = 'pen' }
        elseif ($b.Audio -or $name -match '(?i)bud|pods|head|\bear|wh-|wf-|barracuda|arctis|hyperx|quietcomfort|jabra|beats') { $kind = 'headphones' }

        [pscustomobject]@{ Mac = $mac; Name = $name; Battery = $b.Level; Connected = $connected; Kind = $kind }
    }
}

# ---------- UI ----------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Bluetooth Battery" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="NoResize" ShowInTaskbar="False"
        SizeToContent="Height" Width="290" FontFamily="Segoe UI">
  <Border x:Name="Card" Margin="12" CornerRadius="10" Background="#EB1E1F22"
          BorderBrush="#2EFFFFFF" BorderThickness="1" Padding="14,11,14,10">
    <Border.Effect>
      <DropShadowEffect BlurRadius="18" ShadowDepth="2" Opacity="0.5" Color="Black"/>
    </Border.Effect>
    <StackPanel>
      <DockPanel Margin="0,0,0,6">
        <TextBlock x:Name="Updated" DockPanel.Dock="Right" Foreground="#73FFFFFF"
                   FontSize="11" VerticalAlignment="Center"/>
        <TextBlock x:Name="BtGlyph" FontFamily="Segoe MDL2 Assets" Foreground="#4CC2FF"
                   FontSize="13" VerticalAlignment="Center" Margin="0,0,7,0"/>
        <TextBlock Text="Bluetooth battery" Foreground="#E6FFFFFF" FontSize="12"
                   FontWeight="SemiBold" VerticalAlignment="Center"/>
      </DockPanel>
      <StackPanel x:Name="Rows"/>
      <TextBlock x:Name="Empty" Foreground="#80FFFFFF" FontSize="12" Margin="0,4,0,2"
                 TextWrapping="Wrap" Visibility="Collapsed"
                 Text="Loading…"/>
    </StackPanel>
  </Border>
</Window>
'@

$window  = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$Card    = $window.FindName('Card')
$Rows    = $window.FindName('Rows')
$Empty   = $window.FindName('Empty')
$Updated = $window.FindName('Updated')
$window.FindName('BtGlyph').Text = [string][char]0xE702

$Glyphs = @{
    keyboard   = 0xE765; mouse = 0xE962; headphones = 0xE7F6; speaker = 0xE7F5
    controller = 0xE7FC; pen = 0xEDC6; generic = 0xE702
}

$RowTemplate = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      Margin="0,5,0,5" Opacity="{OP}" ToolTip="{TIP}" Background="Transparent" Tag="{MAC}">
  <Grid.ColumnDefinitions>
    <ColumnDefinition Width="30"/>
    <ColumnDefinition Width="*"/>
  </Grid.ColumnDefinitions>
  <TextBlock FontFamily="Segoe MDL2 Assets" Text="{GLYPH}" FontSize="17"
             Foreground="#D9FFFFFF" VerticalAlignment="Center"/>
  <StackPanel Grid.Column="1">
    <DockPanel>
      <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" Margin="8,0,0,0">
        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE945;" Foreground="{COLOR}" FontSize="11"
                   VerticalAlignment="Center" Margin="0,1,3,0" Visibility="{BOLTVIS}"/>
        <TextBlock Text="{PCT}%" Foreground="{COLOR}" FontSize="12" FontWeight="SemiBold"/>
      </StackPanel>
      <Grid>
        <TextBlock x:Name="NameText" Text="{NAME}" Foreground="#F2FFFFFF" FontSize="12"
                   TextTrimming="CharacterEllipsis"/>
        <TextBox x:Name="NameBox" Visibility="Collapsed" FontSize="12" Margin="-3,-2,0,-2"
                 Padding="1,0,1,0" Foreground="White" Background="#33FFFFFF" BorderBrush="#4CC2FF"
                 BorderThickness="1" CaretBrush="White" SelectionBrush="#4CC2FF" Tag="{MAC}"/>
      </Grid>
    </DockPanel>
    <Grid Height="6" Margin="0,4,0,0">
      <Border CornerRadius="3" Background="#24FFFFFF"/>
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="{P}*"/>
          <ColumnDefinition Width="{Q}*"/>
        </Grid.ColumnDefinitions>
        <Border CornerRadius="3" Background="{COLOR}">{PULSE}</Border>
      </Grid>
    </Grid>
  </StackPanel>
</Grid>
'@

$PulseXaml = @'
<Border.Triggers>
  <EventTrigger RoutedEvent="FrameworkElement.Loaded">
    <BeginStoryboard><Storyboard>
      <DoubleAnimation Storyboard.TargetProperty="Opacity" From="1" To="0.45"
                       Duration="0:0:1.1" AutoReverse="True" RepeatBehavior="Forever"/>
    </Storyboard></BeginStoryboard>
  </EventTrigger>
</Border.Triggers>
'@

# ---------- charging detection ----------
# Windows doesn't expose a charging flag for Bluetooth devices, so infer it:
# a connected device whose reported level goes UP between two polls is charging.
# The state is kept while the level holds steady, cleared when it drops,
# when the device disconnects, or after $ChargeHold with no further rise.
$script:History = @{}
$ChargeHold = [TimeSpan]::FromMinutes(30)

function Update-ChargeState($list) {
    $now = Get-Date
    foreach ($d in $list) {
        $h = $script:History[$d.Mac]
        $charging = $false; $lastRise = $null
        if ($h -and $d.Connected -and $h.Connected) {
            if ($d.Battery -gt $h.Level)     { $charging = $true; $lastRise = $now }
            elseif ($d.Battery -eq $h.Level -and $h.Charging -and ($now - $h.LastRise) -lt $ChargeHold) {
                $charging = $true; $lastRise = $h.LastRise
            }
        }
        $script:History[$d.Mac] = @{ Level = $d.Battery; Connected = $d.Connected; Charging = $charging; LastRise = $lastRise }
        $d | Add-Member -NotePropertyName Charging -NotePropertyValue $charging -Force
    }
}

function Get-DisplayName($d) {
    $a = $script:Settings.Aliases[$d.Mac]
    if ($a) { $a } else { $d.Name }
}

function New-Row($d, [string]$displayName) {
    $pct = [Math]::Max(0, [Math]::Min(100, [int]$d.Battery))
    $color = if ($d.Charging) { '#4CC2FF' } elseif ($pct -lt 20) { '#FF6B6B' } elseif ($pct -lt 50) { '#F5C542' } else { '#5FD068' }
    $who = if ($script:Settings.Aliases[$d.Mac]) { "$displayName ($($d.Name))" } else { $displayName }
    $tip = if (-not $d.Connected) { "$who — disconnected (last known $pct%)" }
           elseif ($d.Charging)   { "$who — charging, $pct% (detected from rising level)" }
           else                   { "$who — $pct%" }
    $g = $Glyphs[$d.Kind]; if (-not $g) { $g = $Glyphs.generic }
    $esc = { param($s) [System.Security.SecurityElement]::Escape([string]$s) }
    $x = $RowTemplate.
        Replace('{OP}', $(if ($d.Connected) { '1' } else { '0.42' })).
        Replace('{TIP}', (& $esc $tip)).
        Replace('{GLYPH}', ('&#x{0:X};' -f $g)).
        Replace('{PCT}', $pct).
        Replace('{COLOR}', $color).
        Replace('{NAME}', (& $esc $displayName)).
        Replace('{BOLTVIS}', $(if ($d.Charging) { 'Visible' } else { 'Collapsed' })).
        Replace('{PULSE}', $(if ($d.Charging) { $PulseXaml } else { '' })).
        Replace('{P}', $pct).
        Replace('{Q}', (100 - $pct)).
        Replace('{MAC}', $d.Mac)
    $row = [Windows.Markup.XamlReader]::Parse($x)
    $box = $row.FindName('NameBox')
    $box.Add_KeyDown({
        if ($_.Key -eq 'Return')     { $_.Handled = $true; Complete-Rename $this $true }
        elseif ($_.Key -eq 'Escape') { $_.Handled = $true; Complete-Rename $this $false }
    })
    $box.Add_LostKeyboardFocus({ Complete-Rename $this $true })
    $row
}

# ---------- renaming ----------
# Double-click a device (or right-click > Rename) to edit its name in place.
# Enter or clicking away saves, Esc cancels; an empty name restores the original.
$script:Editing = $false

function Find-Row($element) {
    $e = $element
    while ($e) {
        if ($e -is [System.Windows.FrameworkElement] -and $e.Parent -eq $Rows) { return $e }
        $p = $null
        if ($e -is [System.Windows.Media.Visual]) { $p = [System.Windows.Media.VisualTreeHelper]::GetParent($e) }
        if (-not $p) { $p = [System.Windows.LogicalTreeHelper]::GetParent($e) }
        $e = $p
    }
}

function Start-Rename($row) {
    if (-not $row -or $script:Editing) { return }
    $mac = [string]$row.Tag
    $d = $script:LastData | Where-Object Mac -eq $mac | Select-Object -First 1
    if (-not $d) { return }
    $script:Editing = $true
    $text = $row.FindName('NameText'); $box = $row.FindName('NameBox')
    $box.Text = Get-DisplayName $d
    $text.Visibility = 'Hidden'; $box.Visibility = 'Visible'
    $window.Activate() | Out-Null
    [void]$box.Focus(); [void][System.Windows.Input.Keyboard]::Focus($box)
    $box.SelectAll()
}

function Complete-Rename($box, [bool]$save) {
    if (-not $script:Editing) { return }
    $script:Editing = $false
    if ($save) {
        $mac = [string]$box.Tag
        $new = $box.Text.Trim()
        $d = $script:LastData | Where-Object Mac -eq $mac | Select-Object -First 1
        if (-not $new -or ($d -and $new -ceq $d.Name)) { $script:Settings.Aliases.Remove($mac) }
        else { $script:Settings.Aliases[$mac] = $new }
        Save-Settings
    }
    Show-Devices
}

$script:LastData = $null
function Show-Devices {
    if ($script:Editing) { return }   # don't rebuild rows under an open name editor
    $list = @($script:LastData)
    $show = @($list | Where-Object { $_ -and ($_.Connected -or $script:Settings.ShowDisconnected) } |
              Sort-Object @{ e = { -not $_.Connected } }, @{ e = { Get-DisplayName $_ } })
    # Disambiguate un-renamed devices that share a name (e.g. two mice of the same model)
    $dupes = $show | Where-Object { -not $script:Settings.Aliases[$_.Mac] } |
             Group-Object Name | Where-Object Count -gt 1 | ForEach-Object Name
    $Rows.Children.Clear()
    foreach ($d in $show) {
        $label = Get-DisplayName $d
        if (-not $script:Settings.Aliases[$d.Mac] -and $dupes -contains $d.Name) { $label = "$($d.Name) ($($d.Mac.Substring(8)))" }
        try { [void]$Rows.Children.Add((New-Row $d $label)) } catch { Write-Log "row: $_" }
    }
    if ($show.Count -eq 0) {
        $Empty.Text = if ($list.Count -eq 0) { 'No Bluetooth devices are reporting battery.' }
                      else { 'No connected devices are reporting battery. Right-click › Show disconnected devices.' }
        $Empty.Visibility = 'Visible'
    } else { $Empty.Visibility = 'Collapsed' }
    $Updated.Text = (Get-Date).ToShortTimeString()
}

# ---------- background refresh ----------
$iss = [initialsessionstate]::CreateDefault()
$script:Runspace = [runspacefactory]::CreateRunspace($iss)
$script:Runspace.Open()
$script:PS = [powershell]::Create()
$script:PS.Runspace = $script:Runspace
$script:Pending = $null

function Start-Refresh {
    if ($script:Pending) { return }
    $script:PS.Commands.Clear()
    [void]$script:PS.AddScript($Collector)
    $script:Pending = $script:PS.BeginInvoke()
}

$poll = New-Object System.Windows.Threading.DispatcherTimer
$poll.Interval = [TimeSpan]::FromMilliseconds(400)
$poll.Add_Tick({
    if ($script:Pending -and $script:Pending.IsCompleted) {
        try {
            $res = $script:PS.EndInvoke($script:Pending)
            $script:LastData = @($res | Where-Object { $_ })
            Update-ChargeState $script:LastData
            Show-Devices
        } catch { Write-Log "refresh: $_" }
        finally { $script:Pending = $null }
    }
})
$poll.Start()

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds([Math]::Max(15, [int]$script:Settings.RefreshSeconds))
$timer.Add_Tick({ Start-Refresh })
$timer.Start()

# ---------- start with Windows ----------
function Set-Startup([bool]$enable) {
    if (-not $enable) { Remove-Item -LiteralPath $StartupLnk -ErrorAction SilentlyContinue; return }
    # Install a stable copy under %LOCALAPPDATA% so startup doesn't depend on where this file lives
    $srcDir = Split-Path -Parent $PSCommandPath
    if ($srcDir -ne $DataDir) {
        Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DataDir 'BluetoothBatteryWidget.ps1') -Force
        $vbs = Join-Path $srcDir 'launch.vbs'
        if (Test-Path $vbs) { Copy-Item -LiteralPath $vbs -Destination (Join-Path $DataDir 'launch.vbs') -Force }
    }
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($StartupLnk)
    $lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $lnk.Arguments = '"' + (Join-Path $DataDir 'launch.vbs') + '"'
    $lnk.WorkingDirectory = $DataDir
    $lnk.IconLocation = (Join-Path $env:WINDIR 'System32\bthprops.cpl') + ',0'
    $lnk.Description = 'Battery levels of your Bluetooth devices'
    $lnk.Save()
}

# ---------- context menu ----------
function New-MenuItem($header, [bool]$checkable = $false, [bool]$checked = $false) {
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = $header
    $mi.IsCheckable = $checkable
    $mi.IsChecked = $checked
    $mi
}
$menu = New-Object System.Windows.Controls.ContextMenu
$miRefresh  = New-MenuItem 'Refresh now'
$miShowDisc = New-MenuItem 'Show disconnected devices' $true ([bool]$script:Settings.ShowDisconnected)
$miTopmost  = New-MenuItem 'Always on top' $true ([bool]$script:Settings.Topmost)
$miStartup  = New-MenuItem 'Start with Windows' $true (Test-Path $StartupLnk)
$miExit     = New-MenuItem 'Close widget'
# Per-device items: only shown when the menu is opened over a device row
$miRename    = New-MenuItem 'Rename…'
$miResetName = New-MenuItem 'Restore original name'
$sepDevice   = New-Object System.Windows.Controls.Separator
foreach ($i in $miRename, $miResetName, $sepDevice) { [void]$menu.Items.Add($i) }
foreach ($i in $miRefresh, $miShowDisc, $miTopmost, $miStartup) { [void]$menu.Items.Add($i) }
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$menu.Items.Add($miExit)
$Card.ContextMenu = $menu

$miRefresh.Add_Click({ $Updated.Text = '…'; Start-Refresh })
$miShowDisc.Add_Click({
    $script:Settings.ShowDisconnected = $miShowDisc.IsChecked; Save-Settings; Show-Devices
})
$miTopmost.Add_Click({
    $script:Settings.Topmost = $miTopmost.IsChecked; $window.Topmost = $miTopmost.IsChecked; Save-Settings
})
$miStartup.Add_Click({
    try { Set-Startup $miStartup.IsChecked }
    catch {
        Write-Log "startup: $_"
        $miStartup.IsChecked = (Test-Path $StartupLnk)
        [System.Windows.MessageBox]::Show("Couldn't update startup setting:`n$_", 'Bluetooth Battery') | Out-Null
    }
})
$miExit.Add_Click({ $window.Close() })

$script:MenuRow = $null
$Card.Add_ContextMenuOpening({
    $script:MenuRow = Find-Row $_.OriginalSource
    $d = if ($script:MenuRow) { $script:LastData | Where-Object Mac -eq ([string]$script:MenuRow.Tag) | Select-Object -First 1 }
    if ($d) {
        $miRename.Header = 'Rename "' + ((Get-DisplayName $d) -replace '_', '__') + '"…'
        $miRename.Visibility = 'Visible'; $sepDevice.Visibility = 'Visible'
        $hasAlias = [bool]$script:Settings.Aliases[$d.Mac]
        $miResetName.Header = 'Restore original name (' + ($d.Name -replace '_', '__') + ')'
        $miResetName.Visibility = $(if ($hasAlias) { 'Visible' } else { 'Collapsed' })
    } else {
        $miRename.Visibility = 'Collapsed'; $miResetName.Visibility = 'Collapsed'; $sepDevice.Visibility = 'Collapsed'
    }
})
$miRename.Add_Click({
    # Wait for the menu to close so it doesn't take focus back from the editor
    [void]$window.Dispatcher.BeginInvoke([Action]{ Start-Rename $script:MenuRow }, [System.Windows.Threading.DispatcherPriority]::Background)
})
$miResetName.Add_Click({
    if ($script:MenuRow) { $script:Settings.Aliases.Remove([string]$script:MenuRow.Tag); Save-Settings; Show-Devices }
})

# ---------- window behaviour ----------
$Card.Add_MouseLeftButtonDown({
    if ($_.ClickCount -eq 2) {
        $row = Find-Row $_.OriginalSource
        if ($row) { $_.Handled = $true; Start-Rename $row; return }
    }
    try { $window.DragMove() } catch {}
    $script:Settings.Left = [int]$window.Left
    $script:Settings.Top  = [int]$window.Top
    Save-Settings
})

# Hide from Alt+Tab (tool window style)
if (-not ('BTW.Native' -as [type])) {
    Add-Type -Namespace BTW -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
'@
}
$window.Add_SourceInitialized({
    $h = (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle
    $ex = [BTW.Native]::GetWindowLong($h, -20)
    [void][BTW.Native]::SetWindowLong($h, -20, ($ex -bor 0x80))   # WS_EX_TOOLWINDOW
})

# Initial position: saved spot if it's still on screen, else top-right of the work area
$vs = [System.Windows.SystemParameters]
$wa = $vs::WorkArea
$window.WindowStartupLocation = 'Manual'
$left = $script:Settings.Left; $top = $script:Settings.Top
if ($null -ne $left -and $null -ne $top -and
    $left -ge $vs::VirtualScreenLeft - 50 -and $left -le ($vs::VirtualScreenLeft + $vs::VirtualScreenWidth - 80) -and
    $top  -ge $vs::VirtualScreenTop - 20  -and $top  -le ($vs::VirtualScreenTop + $vs::VirtualScreenHeight - 60)) {
    $window.Left = $left; $window.Top = $top
} else {
    $window.Left = $wa.Right - $window.Width - 8
    $window.Top  = $wa.Top + 8
}
$window.Topmost = [bool]$script:Settings.Topmost

$window.Add_Closed({
    $poll.Stop(); $timer.Stop()
    try { $script:PS.Dispose(); $script:Runspace.Dispose() } catch {}
    try { $script:Mutex.ReleaseMutex() } catch {}
})

$Empty.Visibility = 'Visible'
Start-Refresh
try {
    [void]$window.ShowDialog()
} catch {
    Write-Log "fatal: $_"
    throw
}

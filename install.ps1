<#
  Windows Battery Widget - installer

  Installs the widget for the current user (no admin rights needed):
    - copies it to %LOCALAPPDATA%\BTBatteryWidget
    - adds a Start menu shortcut ("Bluetooth Battery Widget")
    - starts it automatically when you sign in (skip with -NoStartup)
    - launches it

  Usage:
    .\install.ps1                 install or update
    .\install.ps1 -NoStartup      install without starting with Windows
    .\install.ps1 -Uninstall      remove the widget, its shortcuts and settings

  Works from a downloaded copy of the repository, or straight from GitHub:
    irm https://raw.githubusercontent.com/mshajarrazip/Windows-Battery-Widget/main/install.ps1 | iex
#>
param(
    [switch]$Uninstall,
    [switch]$NoStartup,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

$AppName      = 'BTBatteryWidget'
$InstallDir   = Join-Path $env:LOCALAPPDATA $AppName
$RepoRaw      = 'https://raw.githubusercontent.com/mshajarrazip/Windows-Battery-Widget/main'
$Files        = 'BluetoothBatteryWidget.ps1', 'launch.vbs'
$ShortcutName = 'Bluetooth Battery Widget.lnk'
$StartMenuLnk = Join-Path ([Environment]::GetFolderPath('Programs')) $ShortcutName
$StartupLnk   = Join-Path ([Environment]::GetFolderPath('Startup')) $ShortcutName

function Write-Step($msg) { Write-Host "  > $msg" -ForegroundColor Cyan }

function Stop-Widget {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*BluetoothBatteryWidget.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function New-Shortcut($path) {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($path)
    $lnk.TargetPath       = Join-Path $env:WINDIR 'System32\wscript.exe'
    $lnk.Arguments        = '"' + (Join-Path $InstallDir 'launch.vbs') + '"'
    $lnk.WorkingDirectory = $InstallDir
    $lnk.IconLocation     = (Join-Path $env:WINDIR 'System32\bthprops.cpl') + ',0'
    $lnk.Description      = 'Battery levels of your Bluetooth devices'
    $lnk.Save()
}

Write-Host ''
Write-Host 'Windows Battery Widget' -ForegroundColor White

# ---------- uninstall ----------
if ($Uninstall) {
    Write-Step 'Closing the widget'
    Stop-Widget
    Start-Sleep -Milliseconds 500
    Write-Step 'Removing shortcuts'
    Remove-Item -LiteralPath $StartMenuLnk, $StartupLnk -Force -ErrorAction SilentlyContinue
    Write-Step "Removing $InstallDir"
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host 'Uninstalled.' -ForegroundColor Green
    return
}

# ---------- install / update ----------
Write-Step 'Closing the widget if it is running'
Stop-Widget

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# Use files next to this script if present; otherwise download them from GitHub
$localDir = if ($PSScriptRoot) { $PSScriptRoot } else { $null }
$haveLocal = $localDir -and -not ($Files | Where-Object { -not (Test-Path (Join-Path $localDir $_)) })

foreach ($f in $Files) {
    $dest = Join-Path $InstallDir $f
    if ($haveLocal) {
        if ((Resolve-Path $localDir).Path -ne (Resolve-Path $InstallDir).Path) {
            Write-Step "Copying $f"
            Copy-Item -LiteralPath (Join-Path $localDir $f) -Destination $dest -Force
        }
    } else {
        Write-Step "Downloading $f"
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "$RepoRaw/$f" -OutFile $dest -UseBasicParsing
    }
    Unblock-File -LiteralPath $dest -ErrorAction SilentlyContinue
}

Write-Step 'Adding Start menu shortcut'
New-Shortcut $StartMenuLnk

if ($NoStartup) {
    Remove-Item -LiteralPath $StartupLnk -Force -ErrorAction SilentlyContinue
} else {
    Write-Step 'Setting it to start when you sign in'
    New-Shortcut $StartupLnk
}

if (-not $NoLaunch) {
    Write-Step 'Starting the widget'
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"' + (Join-Path $InstallDir 'launch.vbs') + '"')
}

Write-Host ''
Write-Host 'Installed!' -ForegroundColor Green
if (-not $NoLaunch) {
    Write-Host '  The widget is in the top-right corner of your screen. Drag it to move it,'
    Write-Host '  right-click it for options.'
}
Write-Host '  Open it any time from "Bluetooth Battery Widget" in the Start menu.'
Write-Host ''

# Windows Battery Widget

A small desktop widget for Windows that shows the battery level of your Bluetooth devices: keyboards, mice, headsets, speakers and so on, all in one place.

Made with [Claude](https://claude.ai).

## Features

- One row per device: icon, name, battery bar and percentage
- Colour-coded bars: green (50%+), amber (20–49%), red (under 20%)
- **Charging indicator:** a blue, pulsing bar with a ⚡ when a device is charging
- **Rename devices:** give any device your own display name
- Optionally shows paired-but-disconnected devices (faded, with their last known level)
- Drag it anywhere; it remembers its position
- Optional *Always on top* and *Start with Windows*
- Updates every 60 seconds; no extra software or admin rights needed, and nothing in the taskbar

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built into Windows)

## Install

No admin rights needed. Choose one of these:

**Option A: one command.** Open PowerShell and paste:

```powershell
irm https://raw.githubusercontent.com/mshajarrazip/Windows-Battery-Widget/main/install.ps1 | iex
```

**Option B: download.** Click **Code › Download ZIP** on this page, extract it, then double-click **`install.cmd`**.

Either way, the installer:

- copies the widget to `%LOCALAPPDATA%\BTBatteryWidget`
- adds **Bluetooth Battery Widget** to the Start menu
- sets it to start when you sign in
- starts it. The widget appears in the top-right corner of your main screen.

Running the installer again updates the widget to the latest version and keeps your settings.

To install without starting with Windows, run `install.ps1 -NoStartup` from PowerShell instead. You can also turn startup on or off later from the widget's right-click menu.

### Uninstall

Double-click **`uninstall.cmd`**, or run `install.ps1 -Uninstall`. This closes the widget and removes it, its shortcuts and its settings.

### Run without installing

Double-click **`launch.vbs`** in the downloaded folder. Only one copy of the widget runs at a time.

## Using it

| To… | Do this |
| --- | --- |
| Move the widget | Drag it |
| Rename a device | Double-click its name, or right-click it › **Rename**. Press Enter to save or Esc to cancel |
| Restore a device's original name | Right-click it › **Restore original name**, or clear the name and save |
| See devices that aren't connected | Right-click › **Show disconnected devices** |
| Keep it above other windows | Right-click › **Always on top** |
| Start it when you sign in | Right-click › **Start with Windows** |
| Close it | Right-click › **Close widget** |

Hover over a device to see its full name and status.

## How it works

Windows already stores the battery level that it shows under *Settings › Bluetooth & devices*. The widget reads that value (`DEVPKEY_Bluetooth_Battery`) from each Bluetooth device, together with whether the device is currently connected. It does this in a background thread so the widget stays responsive.

**Charging:** Windows doesn't expose whether a Bluetooth device is charging, so the widget works it out instead. If a connected device's level *goes up* between two readings, it's marked as charging. The indicator stays on while the level holds steady, and it goes off when the level drops, when the device disconnects, or after 30 minutes with no further rise. Because of this, the charging indicator appears only after the first rise in the reading, usually 5–15 minutes after plugging in.

## Limitations

- Only devices that report their battery to Windows appear. If Windows doesn't show a battery level for a device in Settings, the widget can't either.
- Devices connected through a USB receiver (for example Logitech Bolt or Unifying) rather than Bluetooth aren't included.
- Windows updates battery levels on its own schedule, so readings can be a few minutes behind the device.
- Device icons are picked from the device type and name, so an unusual device may get a generic Bluetooth icon.

## Files

| File | Purpose |
| --- | --- |
| `BluetoothBatteryWidget.ps1` | The widget |
| `launch.vbs` | Starts the widget without a console window |
| `install.ps1` | Installs, updates or uninstalls the widget |
| `install.cmd` / `uninstall.cmd` | Double-click shortcuts for the installer |

Settings (position, options and custom names) are saved in `%LOCALAPPDATA%\BTBatteryWidget\settings.json`.

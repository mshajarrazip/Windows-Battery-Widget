@echo off
rem Double-click to remove the Windows Battery Widget, its shortcuts and settings.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Uninstall
echo.
pause

@echo off
rem John's Toolkit - debug start: a visible window shows every step and any error.
echo Starting John's Toolkit in debug mode...
echo A PowerShell window will open (after the administrator prompt) and stay open.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -STA -NoExit -File \"%~dp0app\Launcher.ps1\" -DebugMode'"
if errorlevel 1 (echo. & echo The administrator prompt was cancelled or blocked. & pause)

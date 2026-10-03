@echo off
rem John's Toolkit by nmx88 - Windows 10/11
rem Asks for administrator rights from this visible window, so the Windows prompt appears in front.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"%~dp0app\Launcher.ps1\"'"
if errorlevel 1 (echo. & echo John's Toolkit needs administrator rights. The prompt was cancelled or blocked. & echo If it keeps failing, run Start-Debug.bat & pause)

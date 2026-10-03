@echo off
rem John's Toolkit - classic console mode (Greek)
powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0classic\_loader.ps1\"'"

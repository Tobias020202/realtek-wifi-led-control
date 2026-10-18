@echo off
title Realtek Wi-Fi LED: off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-RealtekWifiLed.ps1" -Value 0 -Pause

@echo off
title Realtek Wi-Fi LED: blink
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-RealtekWifiLed.ps1" -Value 1 -Pause

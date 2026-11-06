@echo off
:: Universal System Disk Cleaner Launcher
:: Automatically triggers PowerShell with ExecutionPolicy Bypass as Administrator
title Universal System Disk Cleaner

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SystemDiskCleaner.ps1"
if %errorlevel% neq 0 (
    echo.
    echo If execution failed, please right click this file and select 'Run as administrator'.
    pause
)

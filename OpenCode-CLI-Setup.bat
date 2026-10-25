@echo off
rem ============================================================================
rem  OpenCode CLI Setup - launcher
rem  Copyright (c) 2026 Mohamed Abd El-Hafez. All rights reserved.
rem  Independent community installer utility. Not affiliated with OpenCode.
rem ============================================================================
setlocal EnableExtensions
title OpenCode CLI - Setup

set "APP_DIR=%~dp0"
set "APP_PS1=%APP_DIR%OpenCode-CLI-Setup.ps1"

if not exist "%APP_PS1%" (
    echo.
    echo [ERROR] Companion script not found:
    echo         %APP_PS1%
    echo.
    echo Keep OpenCode-CLI-Setup.bat and OpenCode-CLI-Setup.ps1 in the same folder.
    echo.
    pause
    exit /b 2
)

set "PS_EXE="
if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not defined PS_EXE (
    where powershell.exe >nul 2>&1
    if not errorlevel 1 set "PS_EXE=powershell.exe"
)
if not defined PS_EXE (
    echo.
    echo [ERROR] Windows PowerShell was not found on this computer.
    echo         OpenCode CLI Setup requires Windows PowerShell 5.1 or newer.
    echo.
    pause
    exit /b 3
)

rem ExecutionPolicy Bypass applies to this single process only; nothing is changed system-wide.
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%APP_PS1%"
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
    echo.
    echo [ERROR] OpenCode CLI Setup stopped with exit code %RC%.
    echo.
    pause
)

endlocal & exit /b %RC%

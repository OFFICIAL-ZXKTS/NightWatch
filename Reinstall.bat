@echo off
title SleepSafe Reinstaller
cd /d "%~dp0"

:: Self-elevate to Administrator if not already.
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator permissions via UAC...
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    if errorlevel 1 (
        echo.
        echo Failed to elevate. Right-click Reinstall.bat and choose "Run as administrator".
        pause
    )
    exit /b
)

echo ======================================================
echo       SleepSafe - Performing Fresh Reinstall
echo ======================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-StudySafetySystem.ps1"
if errorlevel 1 (
    echo.
    echo ======================================================
    echo Reinstall FAILED. Please scroll up and read the errors.
    echo ======================================================
) else (
    echo.
    echo ======================================================
    echo Reinstall completed successfully!
    echo ======================================================
)
pause

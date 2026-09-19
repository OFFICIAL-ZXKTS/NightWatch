@echo off
title SlumberGuard Reinstaller
cd /d "%~dp0"

:: Check for Administrator privileges and self-elevate if needed
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator permissions...
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo ======================================================
echo       SlumberGuard - Performing Fresh Reinstall
echo ======================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-StudySafetySystem.ps1"

echo.
echo ======================================================
echo Reinstall completed successfully!
echo ======================================================
pause

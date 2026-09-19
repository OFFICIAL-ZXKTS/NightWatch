@echo off
title Study Break Signal
:: Resolve Desktop path dynamically
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "[System.Environment]::GetFolderPath('Desktop')"`) do set "DESKTOP_DIR=%%I"
if not defined DESKTOP_DIR set "DESKTOP_DIR=%USERPROFILE%\Desktop"

:: Execute the PowerShell script to toggle break signal without forcing sleep
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0StudyBreak.ps1"
